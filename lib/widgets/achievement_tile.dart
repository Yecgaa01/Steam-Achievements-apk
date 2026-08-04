import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_text.dart';
import '../models/steam_models.dart';

class AchievementTile extends StatefulWidget {
  final SteamAchievement achievement;
  final AppText text;
  final bool revealHiddenByDefault;
  final bool showRarityTier;
  final bool showObtainabilityBadge;

  final bool isPinned;
  final VoidCallback? onTogglePinned;

  const AchievementTile({
    super.key,
    required this.achievement,
    required this.text,
    this.revealHiddenByDefault = false,
    this.showRarityTier = true,
    this.showObtainabilityBadge = true,
    this.isPinned = false,
    this.onTogglePinned,
  });

  @override
  State<AchievementTile> createState() => _AchievementTileState();
}

class _AchievementTileState extends State<AchievementTile> {
  bool _revealed = false;

  @override
  void didUpdateWidget(covariant AchievementTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.achievement.apiName != widget.achievement.apiName) {
      _revealed = false;
    }
  }

  String? _rarityTier(double? percent) {
    if (percent == null) return null;
    if (percent < 1) return widget.text.rarityMythic;
    if (percent < 5) return widget.text.rarityLegendary;
    if (percent < 10) return widget.text.rarityVeryRare;
    if (percent < 20) return widget.text.rarityRare;
    if (percent < 50) return widget.text.rarityUncommon;
    return widget.text.rarityCommon;
  }

  Color? _rarityTierColor(double? percent) {
    if (percent == null) return null;
    if (percent < 1) return const Color(0xFFFFD700);
    if (percent < 5) return const Color(0xFFFF8000);
    if (percent < 10) return const Color(0xFFA335EE);
    if (percent < 20) return const Color(0xFF0070DD);
    if (percent < 50) return const Color(0xFF1EFF00);
    return const Color(0xFF9D9D9D);
  }

  String? _obtainabilityLabel() {
    if (!widget.showObtainabilityBadge) return null;
    if (widget.achievement.obtainability == 1) {
      return widget.text.obtainabilityBugged;
    }
    if (widget.achievement.obtainability == 2) {
      return widget.text.obtainabilityConditional;
    }
    if (widget.achievement.obtainability == 3) {
      return widget.text.obtainabilityUnobtainable;
    }
    return null;
  }

  Color? _obtainabilityColor(bool dark) {
    if (widget.achievement.obtainability == 1) {
      return dark ? const Color(0xFFF97316) : const Color(0xFFC2410C);
    }
    if (widget.achievement.obtainability == 2) {
      return dark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1);
    }
    if (widget.achievement.obtainability == 3) {
      return dark ? const Color(0xFFF87171) : const Color(0xFFB91C1C);
    }
    return null;
  }

  String _formatUnlockDateTime(BuildContext context, int unixSeconds) {
    final date =
        DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true)
            .toLocal();
    final localizations = MaterialLocalizations.of(context);
    final dateText = localizations.formatShortDate(date);
    final timeText = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '$dateText $timeText';
  }

  @override
  Widget build(BuildContext context) {
    final achievement = widget.achievement;
    final text = widget.text;
    final iconUrl =
        achievement.achieved ? achievement.icon : achievement.iconGray;
    final percent = achievement.globalPercent == null
        ? ''
        : '${achievement.globalPercent!.toStringAsFixed(1)}%';
    final rarityTier = _rarityTier(achievement.globalPercent);
    final rarityTierColor = _rarityTierColor(achievement.globalPercent);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldColor = Theme.of(context).scaffoldBackgroundColor;
    final isOled = dark &&
        scaffoldColor.r < 0.02 &&
        scaffoldColor.g < 0.02 &&
        scaffoldColor.b < 0.02;
    final tileColor = achievement.achieved
        ? (dark
            ? (isOled ? const Color(0xFF050505) : const Color(0xFF070D24))
            : Colors.white)
        : (dark
            ? (isOled ? const Color(0xFF191919) : const Color(0xFF25293D))
            : const Color(0xFFF1F5F9));
    final borderColor = dark
        ? Colors.white.withValues(alpha: achievement.achieved ? 0.06 : 0.08)
        : const Color(0xFFE2E8F0);
    final subtleText = dark ? Colors.white60 : const Color(0xFF64748B);
    final statusText = dark ? Colors.white60 : const Color(0xFF64748B);
    final placeholderColor =
        dark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0);
    final placeholderIconColor =
        dark ? Colors.white54 : const Color(0xFF64748B);
    final shouldHideDetails =
        achievement.hidden && !widget.revealHiddenByDefault && !_revealed;
    final description = shouldHideDetails
        ? text.hiddenAchievement
        : (achievement.description.isEmpty
            ? text.hiddenDescriptionUnavailable
            : achievement.description);
    final title = shouldHideDetails ? text.hiddenAchievement : achievement.name;

    final obtainabilityLabel = _obtainabilityLabel();
    final obtainabilityColor = _obtainabilityColor(dark);
    final achievementProgress = achievement.progressTotal <= 0
        ? 0.0
        : (achievement.progressCurrent / achievement.progressTotal)
            .clamp(0.0, 1.0);
    final achievementProgressText = achievement.progressTotal <= 0
        ? ''
        : '${achievement.progressCurrent}/${achievement.progressTotal}';
    final unlockDate = achievement.achieved && achievement.unlockTime > 0
        ? _formatUnlockDateTime(context, achievement.unlockTime)
        : '';

    return InkWell(
      onTap: achievement.hidden
          ? () => setState(() => _revealed = !_revealed)
          : null,
      onLongPress: widget.onTogglePinned,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
        decoration: BoxDecoration(
          color: tileColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Opacity(
                opacity: achievement.achieved ? 1 : 0.52,
                child: CachedNetworkImage(
                  imageUrl: iconUrl,
                  width: 42,
                  height: 42,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 42,
                    height: 42,
                    color: placeholderColor,
                    child: Icon(
                        achievement.hidden
                            ? Icons.visibility_off
                            : Icons.emoji_events,
                        color: placeholderIconColor),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Opacity(
                        opacity: achievement.achieved ? 1 : 0.62,
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w800)),
                      )),
                      if (achievement.hidden)
                        const Icon(Icons.visibility_off,
                            size: 16, color: Colors.amber),
                      if (widget.onTogglePinned != null)
                        Tooltip(
                          message: widget.isPinned
                              ? text.unpinAchievement
                              : text.pinAchievement,
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 19,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            onPressed: widget.onTogglePinned,
                            icon: Icon(
                                widget.isPinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                color: widget.isPinned
                                    ? Colors.amber
                                    : subtleText),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Opacity(
                    opacity: achievement.achieved ? 1 : 0.58,
                    child: Text(description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: subtleText, fontSize: 11.5)),
                  ),
                  if (achievementProgressText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: achievementProgress,
                        minHeight: 5,
                        backgroundColor: dark
                            ? const Color(0xFF374151)
                            : const Color(0xFFE2E8F0),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          achievementProgress >= 1
                              ? const Color(0xFF38BDF8)
                              : const Color(0xFFFACC15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      achievementProgressText,
                      style: TextStyle(
                        color: subtleText,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: achievement.achieved
                                  ? Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '${text.unlockedStatus} ',
                                            style: TextStyle(
                                              color: statusText,
                                              fontStyle: FontStyle.normal,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          TextSpan(text: unlockDate),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: subtleText,
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            if (obtainabilityLabel != null &&
                                obtainabilityColor != null) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(obtainabilityLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: obtainabilityColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 46,
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: rarityTier != null && rarityTierColor != null
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.star,
                                        size: 13, color: rarityTierColor),
                                    if (percent.isNotEmpty)
                                      Text(percent,
                                          style: TextStyle(
                                              color: subtleText,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800)),
                                  ],
                                )
                              : percent.isNotEmpty
                                  ? Text(percent,
                                      style: TextStyle(
                                          color: subtleText,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800))
                                  : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
