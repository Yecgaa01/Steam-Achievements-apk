package com.yecgaa.steamachievements

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.concurrent.thread
import kotlin.math.roundToInt

class SteamSyncService : Service() {
    private var running = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Sincronizando perfil Steam", "Preparando sincronização...", 0, 0))
        if (!running) {
            running = true
            thread(name = "SteamSyncService") {
                val wakeLock = acquireWakeLock()
                try {
                    sync()
                    notifyDone("Sincronização concluída", "Cache atualizado com sucesso.")
                } catch (error: Exception) {
                    notifyDone("Falha na sincronização", error.message ?: "Erro desconhecido.")
                } finally {
                    if (wakeLock.isHeld) wakeLock.release()
                    running = false
                    stopForeground(false)
                    stopSelf(startId)
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun acquireWakeLock(): PowerManager.WakeLock {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:SteamSync").apply {
            acquire(30 * 60 * 1000L)
        }
    }

    private fun sync() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val steamId = prefs.getString("flutter.steam_id_64", "")?.trim().orEmpty()
        val apiKey = prefs.getString("flutter.steam_api_key", "")?.trim().orEmpty()
        val languageCode = prefs.getString("flutter.language_code", "pt") ?: "pt"
        val language = if (languageCode == "en") "english" else "brazilian"

        if (steamId.isEmpty() || apiKey.isEmpty()) {
            throw IllegalStateException("SteamID64 ou API key não configurados.")
        }

        updateProgress("Carregando perfil", 0, 0)
        val profile = getJson(
            "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=${enc(apiKey)}&steamids=${enc(steamId)}&format=json"
        ).optJSONObject("response")?.optJSONArray("players")?.optJSONObject(0)
            ?: JSONObject().put("steamid", steamId).put("personaname", "Steam").put("avatarfull", "")

        updateProgress("Carregando biblioteca", 0, 0)
        val owned = getJson(
            "https://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/?key=${enc(apiKey)}&steamid=${enc(steamId)}&format=json&include_appinfo=true&include_played_free_games=true"
        ).optJSONObject("response")?.optJSONArray("games") ?: JSONArray()

        val existingGames = readExistingGames(prefs, steamId)

        val games = mutableListOf<JSONObject>()
        for (index in 0 until owned.length()) {
            val source = owned.optJSONObject(index) ?: continue
            val appId = source.optInt("appid", 0)
            if (appId == 0) continue
            val existingGame = existingGames[appId]
            games.add(
                JSONObject()
                    .put("appid", appId)
                    .put("name", source.optString("name", "App $appId"))
                    .put("playtime_forever", source.optInt("playtime_forever", 0))
                    .put("playtime_2weeks", source.optInt("playtime_2weeks", 0))
                    .put("rtime_last_played", source.optInt("rtime_last_played", existingGame?.optInt("rtime_last_played", 0) ?: 0))
                    .put("latest_achievement_unix", existingGame?.optInt("latest_achievement_unix", 0) ?: 0)
                    .put("unlocked", existingGame?.optInt("unlocked", 0) ?: 0)
                    .put("total", existingGame?.optInt("total", 0) ?: 0)
                    .put("progress_loaded", existingGame?.optBoolean("progress_loaded", false) ?: false)
                    .put("has_achievements", existingGame?.optBoolean("has_achievements", true) ?: true)
                    .put("app_type", existingGame?.optString("app_type", "unknown") ?: "unknown")
                    .put("type_loaded", existingGame?.optBoolean("type_loaded", false) ?: false)
            )
        }
        games.sortBy { it.optString("name").lowercase() }

        prefs.edit()
            .putString("flutter.cache_profile_$steamId", profile.toString())
            .putString("flutter.cache_games_$steamId", JSONObject().put("saved_at", nowIso()).put("games", JSONArray(games)).toString())
            .apply()

        val fullSyncKey = "flutter.sync_full_completed_$steamId"
        val fullSyncCompleted = prefs.getBoolean(fullSyncKey, false)
        val scanCandidates = if (fullSyncCompleted) {
            games.sortedWith(
                compareByDescending<JSONObject> { it.optInt("rtime_last_played", 0) }
                    .thenByDescending { it.optInt("playtime_2weeks", 0) }
                    .thenByDescending { it.optInt("playtime_forever", 0) }
            ).take(RECENT_SYNC_LIMIT)
        } else {
            games
        }

        val total = scanCandidates.size
        for ((index, game) in scanCandidates.withIndex()) {
            val current = index + 1
            updateProgress("Escaneando ${game.optString("name")}", current, total)
            if (game.optBoolean("progress_loaded", false) &&
                !game.optBoolean("has_achievements", true) &&
                game.optInt("playtime_2weeks", 0) == 0
            ) continue
            hydrateGame(apiKey, steamId, language, game)
            if (current % 5 == 0 || current == total) {
                prefs.edit()
                    .putString("flutter.cache_games_$steamId", JSONObject().put("saved_at", nowIso()).put("games", JSONArray(games)).toString())
                    .apply()
            }
        }
        if (!fullSyncCompleted && total == games.size) {
            prefs.edit().putBoolean(fullSyncKey, true).apply()
        }
    }

    private fun readExistingGames(prefs: android.content.SharedPreferences, steamId: String): Map<Int, JSONObject> {
        val cache = prefs.getString("flutter.cache_games_$steamId", null) ?: return emptyMap()
        return try {
            val games = JSONObject(cache).optJSONArray("games") ?: return emptyMap()
            val result = mutableMapOf<Int, JSONObject>()
            for (index in 0 until games.length()) {
                val game = games.optJSONObject(index) ?: continue
                val appId = game.optInt("appid", 0)
                if (appId != 0) result[appId] = game
            }
            result
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun hydrateGame(apiKey: String, steamId: String, language: String, game: JSONObject) {
        val appId = game.optInt("appid")
        try {
            val schema = getJson(
                "https://api.steampowered.com/ISteamUserStats/GetSchemaForGame/v2/?key=${enc(apiKey)}&appid=$appId&l=${enc(language)}",
                noAchievementsOn400 = true,
            ).optJSONObject("game")?.optJSONObject("availableGameStats")?.optJSONArray("achievements") ?: JSONArray()
            if (schema.length() == 0) {
                markNoAchievements(game)
                return
            }

            val player = getJson(
                "https://api.steampowered.com/ISteamUserStats/GetPlayerAchievements/v0001/?key=${enc(apiKey)}&steamid=${enc(steamId)}&appid=$appId&l=${enc(language)}",
                noAchievementsOn400 = true,
            ).optJSONObject("playerstats")?.optJSONArray("achievements") ?: JSONArray()

            var unlocked = 0
            var latestAchievement = 0
            for (i in 0 until player.length()) {
                val achievement = player.optJSONObject(i) ?: continue
                val achieved = achievement.opt("achieved")
                if (achieved == true || achieved == 1 || achieved == "1" || achieved == "true") {
                    unlocked++
                    latestAchievement = maxOf(latestAchievement, achievement.optInt("unlocktime", 0))
                }
            }

            game.put("unlocked", unlocked)
                .put("total", schema.length())
                .put("latest_achievement_unix", latestAchievement)
                .put("progress_loaded", true)
                .put("has_achievements", true)
        } catch (_: NoAchievements) {
            markNoAchievements(game)
        } catch (_: Exception) {
            game.put("progress_loaded", false).put("has_achievements", true)
        }
    }

    private fun markNoAchievements(game: JSONObject) {
        game.put("unlocked", 0)
            .put("total", 0)
            .put("progress_loaded", true)
            .put("has_achievements", false)
    }

    private fun getJson(url: String, noAchievementsOn400: Boolean = false): JSONObject {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 20000
        connection.readTimeout = 20000
        connection.requestMethod = "GET"
        val code = connection.responseCode
        if (code == 400 && noAchievementsOn400) throw NoAchievements()
        if (code == 401 || code == 403) throw IllegalStateException("A Steam recusou o acesso. Confira SteamID64, API key e privacidade do perfil.")
        if (code !in 200..299) throw IllegalStateException("Steam API $code")
        val text = BufferedReader(InputStreamReader(connection.inputStream)).use { it.readText() }
        return JSONObject(text)
    }

    private fun updateProgress(title: String, current: Int, total: Int) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val text = if (total > 0) "$current/$total jogos escaneados" else "Sincronizando..."
        manager.notify(NOTIFICATION_ID, buildNotification(title, text, current, total))
    }

    private fun notifyDone(title: String, text: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(title, text, 0, 0, ongoing = false))
    }

    private fun buildNotification(title: String, text: String, current: Int, total: Int, ongoing: Boolean = true): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(pendingIntent)
            .setOngoing(ongoing)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        if (total > 0) builder.setProgress(total, current.coerceAtMost(total), false)
        return builder.build()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Steam Achievements Sync", NotificationManager.IMPORTANCE_LOW)
        )
    }

    private fun enc(value: String): String = URLEncoder.encode(value, "UTF-8")

    private fun nowIso(): String = java.time.Instant.now().toString()

    private class NoAchievements : Exception()

    companion object {
        private const val CHANNEL_ID = "steam_achievements_sync"
        private const val NOTIFICATION_ID = 1001
        private const val RECENT_SYNC_LIMIT = 20
    }
}
