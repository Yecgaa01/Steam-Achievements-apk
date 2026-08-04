enum AppLanguage { portuguese, english }

class AppText {
  final AppLanguage appLanguage;

  const AppText(this.appLanguage);

  bool get isPt => appLanguage == AppLanguage.portuguese;

  String get appName => 'Steam Achievements';
  String get settings => isPt ? 'Configuração' : 'Settings';
  String get steam => 'Steam';
  String get configHelp => isPt
      ? 'Entre com Steam para mais precisão ou use SteamID64 + Steam Web API key. Os dados ficam salvos só no aparelho.'
      : 'Sign in with Steam for better accuracy, or use SteamID64 + Steam Web API key. Data is stored only on this device.';
  String get steamId64 => 'SteamID64';
  String get apiKey => 'Steam Web API key';
  String get showHidden =>
      isPt ? 'Exibir conquistas ocultas' : 'Show hidden achievements';
  String get showHiddenHelp => isPt
      ? 'Configuração global. Desligado ainda mantém conquistas ocultas visíveis, mas esconde a descrição até você tocar nelas. Para ajustar por jogo, abra a página do jogo.'
      : 'Global setting. When off, hidden achievements remain visible, but descriptions stay hidden until tapped. To adjust per game, open the game page.';
  String get showAverage =>
      isPt ? 'Mostrar média geral no topo' : 'Show overall average on top';
  String get showAverageHelp => isPt
      ? 'A média usa os jogos cujo progresso já foi carregado.'
      : 'The average uses games whose progress has already loaded.';
  String get hideNoAchievements =>
      isPt ? 'Ocultar jogos sem conquistas' : 'Hide games without achievements';
  String get hideNoAchievementsHelp => isPt
      ? 'Jogos detectados sem conquistas somem da lista principal.'
      : 'Games detected without achievements are hidden from the main list.';
  String get language => isPt ? 'Idioma' : 'Language';
  String get portuguese => isPt ? 'Português' : 'Portuguese';
  String get english => isPt ? 'Inglês' : 'English';
  String get save => isPt ? 'Salvar' : 'Save';
  String get saving => isPt ? 'Salvando...' : 'Saving...';
  String get searchGame => isPt ? 'Buscar jogo' : 'Search game';
  String get all => isPt ? 'Todas' : 'All';
  String get unlocked => isPt ? 'Liberadas' : 'Unlocked';
  String get missing => isPt ? 'Faltando' : 'Missing';
  String get hiddenHidden =>
      isPt ? 'Ocultas escondidas' : 'Hidden achievements hidden';
  String get noGameFound =>
      isPt ? 'Nenhum jogo encontrado.' : 'No games found.';
  String get configureFirst =>
      isPt ? 'Configure sua Steam primeiro' : 'Set up Steam first';
  String get configureHelp => isPt
      ? 'Entre com Steam para mais precisão ou use SteamID64 + API key se preferir não fazer login.'
      : 'Sign in with Steam for better accuracy, or use SteamID64 + API key if you prefer not to log in.';
  String get configure => isPt ? 'Configurar' : 'Configure';
  String get loadGamesFailed =>
      isPt ? 'Falha ao carregar jogos' : 'Failed to load games';
  String get retry => isPt ? 'Tentar de novo' : 'Try again';
  String get noAchievements => isPt ? 'Sem conquistas' : 'No achievements';
  String get loadingProgress =>
      isPt ? 'Carregando progresso...' : 'Loading progress...';
  String get progressUnavailable =>
      isPt ? 'Progresso indisponível' : 'Progress unavailable';
  String get averageUnavailable =>
      isPt ? 'Média geral indisponível' : 'Overall average unavailable';
  String previewAchievements(int unlocked, int total) => isPt
      ? '$unlocked/$total conquistas carregadas'
      : '$unlocked/$total achievements loaded';
  String get tapToLoad =>
      isPt ? 'Toque para carregar conquistas' : 'Tap to load achievements';
  String get achievements => isPt ? 'Conquistas' : 'Achievements';
  String achievementsProgress(int unlocked, int total) =>
      isPt ? '$unlocked/$total conquistas' : '$unlocked/$total achievements';
  String get unlockedStatus => isPt ? 'Desbloqueada' : 'Unlocked';
  String get released => isPt ? 'Liberada' : 'Unlocked';
  String get notReleased => isPt ? 'Faltando' : 'Missing';
  String get rarity => isPt ? 'Raridade' : 'Rarity';
  String get hiddenAchievement => isPt
      ? 'Conquista oculta — toque para revelar'
      : 'Hidden achievement — tap to reveal';
  String get hiddenDescriptionUnavailable => isPt
      ? 'A Steam API não disponibilizou a descrição desta conquista oculta.'
      : 'Steam API did not provide the description for this hidden achievement.';
  String get offlineAchievementsCache => isPt
      ? 'Mostrando dados salvos offline.'
      : 'Showing saved offline data.';
  String get offlineAchievementsNoCache => isPt
      ? 'Sem conexão e sem cache deste jogo. Abra esta tela uma vez com internet para salvar as conquistas e poder vê-las offline.'
      : 'Offline and no cache for this game. Open this screen once while online to save achievements for offline viewing.';
  String get firstAchievement =>
      isPt ? 'Primeira conquista' : 'First achievement';
  String get lastAchievement => isPt ? 'Última conquista' : 'Last achievement';
  String get lastPlayed => isPt ? 'Última vez jogado' : 'Last played';
  String get timePlayed => isPt ? 'Tempo jogado' : 'Time played';
  String get unavailableShort => '—';
  String get hideSoftware => isPt ? 'Ocultar não-jogos' : 'Hide non-games';
  String get hideSoftwareHelp => isPt
      ? 'Usa o tipo da loja para ocultar softwares, DLCs, demos e outros itens que não são jogos. Itens desconhecidos aparecem até serem identificados.'
      : 'Uses the Store type to hide software, DLCs, demos, and other non-game items. Unknown items stay visible until identified.';
  String listStatus(int shown, int filtered, int scanned) => isPt
      ? '$shown/$filtered jogos visíveis • $scanned escaneados'
      : '$shown/$filtered visible games • $scanned scanned';
  String get noDescription => isPt ? 'Sem descrição' : 'No description';
  String get searchAchievement =>
      isPt ? 'Buscar conquista' : 'Search achievement';
  String get noAchievementForFilter => isPt
      ? 'Nenhuma conquista para este filtro.'
      : 'No achievements for this filter.';
  String get restoreList => isPt ? 'Recuperar lista' : 'Restore list';
  String get separateDlcAchievements => isPt
      ? 'Separar DLCs e atualizações (experimental)'
      : 'Separate DLCs and updates (experimental)';
  String get separateDlcAchievementsHelp => isPt
      ? 'Tenta agrupar conquistas por DLC/update usando fontes públicas quando disponíveis. Pode falhar ou ficar incompleto.'
      : 'Tries to group achievements by DLC/update using public sources when available. It may fail or be incomplete.';
  String get baseGame => isPt ? 'Jogo base' : 'Base game';
  String get pinnedAchievements => isPt ? 'Fixadas' : 'Pinned';
  String get pinAchievement => isPt ? 'Fixar conquista' : 'Pin achievement';
  String get unpinAchievement =>
      isPt ? 'Desfixar conquista' : 'Unpin achievement';
  String get achievementPinned =>
      isPt ? 'Conquista fixada.' : 'Achievement pinned.';
  String get achievementUnpinned =>
      isPt ? 'Conquista desfixada.' : 'Achievement unpinned.';
  String get achievementHelpTitle =>
      isPt ? 'Dicas de conquistas' : 'Achievement tips';
  String get achievementHelpBody => isPt
      ? 'Toque rapidamente em uma conquista oculta para revelar ou ocultar os detalhes. Segure qualquer conquista para fixá-la no topo. Você pode fixar quantas conquistas quiser.'
      : 'Tap a hidden achievement to reveal or hide its details. Long-press any achievement to pin it to the top. You can pin as many achievements as you want.';
  String get gotIt => isPt ? 'Entendi' : 'Got it';
  String get steamIdHelpLink => isPt
      ? 'Abrir página para descobrir SteamID64'
      : 'Open page to find SteamID64';
  String get apiKeyHelpLink => isPt
      ? 'Abrir página da Steam Web API key'
      : 'Open Steam Web API key page';
  String get steamIdHelpCopied =>
      isPt ? 'Link do SteamID64 copiado.' : 'SteamID64 link copied.';
  String get apiKeyHelpCopied =>
      isPt ? 'Link da API key copiado.' : 'API key link copied.';
  String get hidden => isPt ? 'Ocultas' : 'Hidden';
  String get sortBy => isPt ? 'Ordenar:' : 'Sort:';
  String get sortAchievements =>
      isPt ? 'Ordenar conquistas' : 'Sort achievements';
  String get visibility => isPt ? 'Visibilidade' : 'Visibility';
  String get originalOrder => isPt ? 'Original' : 'Original';
  String get unlockDate => isPt ? 'Data' : 'Date';
  String get hideGame => isPt ? 'Ocultar jogo' : 'Hide game';
  String get showGame => isPt ? 'Reexibir jogo' : 'Show game';
  String get gameHidden => isPt ? 'Jogo ocultado.' : 'Game hidden.';
  String get undo => isPt ? 'Desfazer' : 'Undo';
  String get saveReminder => isPt
      ? 'Alterações só ficam salvas depois de tocar em Salvar.'
      : 'Changes are only kept after tapping Save.';
  String get steamProfileSyncWarning => isPt
      ? 'Devido a limitações da Steam, a sincronização de perfil pode demorar dependendo da quantidade de jogos na conta.'
      : 'Due to Steam limitations, profile sync may take a while depending on how many games are in the account.';
  String get reloadGameProgress =>
      isPt ? 'Recarregar progresso deste jogo' : 'Reload this game progress';
  String get addManualGame =>
      isPt ? 'Adicionar jogo manualmente' : 'Add game manually';
  String get addManualGameTitle =>
      isPt ? 'Adicionar jogo manual' : 'Add manual game';
  String get manualGameInputHint =>
      isPt ? 'Nome, link da Steam ou AppID' : 'Name, Steam link, or AppID';
  String get manualGameNote => isPt
      ? 'Use isto para jogos que não foram detectados porque você não possui diretamente, como compartilhamento de família, fim de semana gratuito ou jogos removidos.'
      : 'Use this for games that were not detected because you do not own them directly, such as family sharing, free weekends, or removed games.';
  String get search => isPt ? 'Buscar' : 'Search';
  String get searching => isPt ? 'Buscando...' : 'Searching...';
  String get adding => isPt ? 'Adicionando...' : 'Adding...';
  String get noManualGameResults =>
      isPt ? 'Nenhum jogo encontrado.' : 'No games found.';
  String get manualGameAlreadyInList => isPt
      ? 'Este jogo já está na lista.'
      : 'This game is already in the list.';
  String get manualGameAddFailed => isPt
      ? 'Não foi possível adicionar este jogo. Ele pode não ter conquistas públicas na Steam ou não ser um jogo.'
      : 'Could not add this game. It may not have public Steam achievements or may not be a game.';
  String get manualGameUpdated =>
      isPt ? 'Link público atualizado.' : 'Public link updated.';
  String get manualGameAdded => isPt ? 'Jogo adicionado.' : 'Game added.';
  String get removeManualGame =>
      isPt ? 'Remover jogo manual' : 'Remove manual game';
  String get manualGameRemoved =>
      isPt ? 'Jogo manual removido.' : 'Manual game removed.';
  String get restoreHiddenGames =>
      isPt ? 'Reexibir jogos ocultos' : 'Show hidden games';
  String get restoreHiddenGamesConfirm => isPt
      ? 'Reexibir todos os jogos ocultos manualmente?'
      : 'Show all manually hidden games?';
  String get restore => isPt ? 'Reexibir' : 'Show';
  String get cancel => isPt ? 'Cancelar' : 'Cancel';
  String get loginMethod => isPt ? 'Método de login' : 'Login method';
  String get steamSessionLogin =>
      isPt ? 'Entrar com Steam' : 'Sign in with Steam';
  String get steamSessionRecommended =>
      isPt ? 'Entrar com Steam (experimental)' : 'Sign in with Steam (experimental)';
  String get steamSessionHelp => isPt
      ? 'Recomendado apenas para jogos privados. Pode expirar após 24h, mas tentará renovar automaticamente.'
      : 'Recommended only for private games. It may expire after 24h, but will try to renew automatically.';
  String get steamSessionSaved =>
      isPt ? 'Sessão Steam salva' : 'Steam session saved';
  String get steamSessionMissing =>
      isPt ? 'Nenhuma sessão Steam' : 'No Steam session';
  String get steamSessionExpired => isPt
      ? 'Sessão expirada. Toque para renovar.'
      : 'Session expired. Tap to renew.';
  String get clearSteamSession =>
      isPt ? 'Sair / limpar sessão' : 'Sign out / clear session';
  String get manualLogin => isPt
      ? 'SteamID64 + API key (opcional)'
      : 'SteamID64 + API key (optional)';
  String get manualLoginHelp => isPt
      ? 'Prefere não entrar com Steam? Continue usando SteamID64 + Steam Web API key. Funciona, mas algumas informações podem ser menos precisas e dependem da privacidade do perfil.'
      : 'Prefer not to sign in with Steam? Keep using SteamID64 + Steam Web API key. It works, but some information may be less accurate and depends on profile privacy.';
  String get useManualLogin =>
      isPt ? 'Usar SteamID64 + API' : 'Use SteamID64 + API';
  String get useSteamSession => isPt ? 'Usar Steam login' : 'Use Steam login';
  String get profileBackground =>
      isPt ? 'Fundo do perfil' : 'Profile background';
  String get profileBackgroundHelp => isPt
      ? 'Escolha uma foto do celular para aparecer somente no card do perfil da página inicial.'
      : 'Choose a photo from this device to show only on the home profile card.';
  String get chooseProfileBackground => isPt ? 'Escolher foto' : 'Choose photo';
  String get removeProfileBackground => isPt ? 'Remover foto' : 'Remove photo';
  String get profileBackgroundSelected =>
      isPt ? 'Foto de fundo selecionada.' : 'Background photo selected.';

  String get themeTab => isPt ? 'Tema' : 'Theme';
  String get themeMode => isPt ? 'Modo do tema' : 'Theme mode';
  String get themeSystem => isPt ? 'Sistema' : 'System';
  String get themeDark => isPt ? 'Escuro' : 'Dark';
  String get themeOled => isPt ? 'Black OLED' : 'Black OLED';
  String get themeLight => isPt ? 'Claro' : 'Light';
  String get showProgressTiers =>
      isPt ? 'Mostrar tiers de progresso' : 'Show progress tiers';
  String get showProgressTiersHelp => isPt
      ? 'Exibe Tava na promoção!, Bronze, Prata, Ouro e Perfeição nos jogos.'
      : 'Shows It was on sale!, Bronze, Silver, Gold, and Perfection on games.';
  String get showRarityTiers =>
      isPt ? 'Mostrar tiers de raridade' : 'Show rarity tiers';
  String get showRarityTiersHelp => isPt
      ? 'Exibe Comum, Rara, Mítica etc. nas conquistas.'
      : 'Shows Common, Rare, Mythic, and other tiers on achievements.';
  String get showObtainabilityBadges => isPt
      ? 'Mostrar status do Steam Hunters (experimental)'
      : 'Show Steam Hunters status (experimental)';
  String get showObtainabilityBadgesHelp => isPt
      ? 'Mostra badges experimentais para conquistas bugadas, condicionais ou impossíveis de obter usando a API do Steam Hunters.'
      : 'Shows experimental badges for bugged, conditional, or unobtainable achievements using the Steam Hunters API.';
  String get goldPerfectGames =>
      isPt ? 'Dourado em jogos perfeitos' : 'Gold on perfect games';
  String get goldPerfectGamesHelp => isPt
      ? 'Usa barra e aro dourados quando o jogo está 100%.'
      : 'Uses gold progress bars and circles when a game is 100%.';
  String get clearCache => isPt ? 'Limpar cache' : 'Clear cache';
  String get clearCacheHelp => isPt
      ? 'Remove perfil, lista, progresso e classificações salvas deste perfil. SteamID64, API key, preferências e jogos ocultos são preservados.'
      : 'Removes saved profile, list, progress, and classifications for this profile. SteamID64, API key, preferences, and hidden games are preserved.';
  String get clearCacheWarning => isPt
      ? 'Limpar cache vai apagar progresso carregado e classificações de jogos/não-jogos salvas. O app terá que consultar a Steam novamente. Usar isso repetidas vezes pode causar um cooldown temporário até a Steam liberar o acesso à loja novamente. Se o problema for só um jogo, segure o toque nele na lista e use “Recarregar progresso deste jogo”.'
      : 'Clearing cache will remove loaded progress and saved game/non-game classifications. The app will need to query Steam again. Repeated use can cause a temporary cooldown until Steam allows Store access again. If the issue is only one game, long-press it in the list and use “Reload this game progress”.';
  String get keepManualGames =>
      isPt ? 'Manter jogos manuais' : 'Keep manual games';
  String get removeManualGamesToo =>
      isPt ? 'Remover tudo' : 'Remove everything';
  String get clearCacheKeepManualHelp => isPt
      ? 'Você quer manter os jogos adicionados manualmente depois de limpar o cache?'
      : 'Do you want to keep manually added games after clearing the cache?';
  String get cacheCleared => isPt ? 'Cache limpo.' : 'Cache cleared.';
  String get tierBoughtOnSale => isPt ? 'Tava na promoção!' : 'It was on sale!';
  String get tierBronze => isPt ? 'Bronze' : 'Bronze';
  String get tierSilver => isPt ? 'Prata' : 'Silver';
  String get tierGold => isPt ? 'Ouro' : 'Gold';
  String get tierPerfect => isPt ? 'Perfeição' : 'Perfection';
  String get obtainabilityBugged => isPt ? 'Bugada' : 'Bugged';
  String get obtainabilityConditional => isPt ? 'Condicional' : 'Conditional';
  String get obtainabilityUnobtainable => isPt ? 'Impossível' : 'Unobtainable';
  String get rarityCommon => isPt ? 'Comum' : 'Common';
  String get rarityUncommon => isPt ? 'Incomum' : 'Uncommon';
  String get rarityRare => isPt ? 'Rara' : 'Rare';
  String get rarityVeryRare => isPt ? 'Muito rara' : 'Very rare';
  String get rarityLegendary => isPt ? 'Lendária' : 'Legendary';
  String get rarityMythic => isPt ? 'Mítica' : 'Mythic';
  String get loginTab => isPt ? 'Login' : 'Login';
  String get settingsTab => isPt ? 'Configurações' : 'Settings';
  String get advancedTab => isPt ? 'Avançado' : 'Advanced';
  String get aboutTab => isPt ? 'Sobre' : 'About';
  String get dataCredits => isPt
      ? 'Desenvolvido com Steam Web API, com dados adicionais de Steam Hunters e Exophase.'
      : 'Powered by Steam Web API with additional data from Steam Hunters and Exophase.';
  String get supportOnKofi => isPt ? 'Apoiar no Ko-fi' : 'Support on Ko-fi';
  String get author => isPt ? 'Autor: Moligon' : 'Author: Moligon';
  String get oldAppDetectedTitle =>
      isPt ? 'Versão antiga detectada' : 'Old version detected';
  String get oldAppDetectedBody => isPt
      ? 'Encontramos uma instalação antiga do Steam Achievements com outro pacote Android. Ela pode aparecer como outro app separado e causar confusão. Recomendamos desinstalar a versão antiga.'
      : 'An older Steam Achievements install with a different Android package was found. It may appear as a separate app and cause confusion. We recommend uninstalling the old version.';
  String get uninstallOldApp =>
      isPt ? 'Desinstalar versão antiga' : 'Uninstall old version';
  String get notNow => isPt ? 'Agora não' : 'Not now';

  String get updateNotificationTitle =>
      isPt ? 'Atualização disponível' : 'Update available';
  String updateNotificationBody(String version) => isPt
      ? 'Toque para abrir o app e instalar a versão $version.'
      : 'Tap to open the app and install version $version.';
  String get version => isPt ? 'Versão' : 'Version';
  String get checkUpdates =>
      isPt ? 'Verificar atualizações' : 'Check for updates';
  String get openLatestRelease =>
      isPt ? 'Abrir release mais recente' : 'Open latest release';
  String get changelog => isPt ? 'Histórico de mudanças' : 'Changelog';
  String get loadingChangelog =>
      isPt ? 'Carregando changelog...' : 'Loading changelog...';
  String get changelogUnavailable => isPt
      ? 'Não foi possível carregar o changelog do GitHub.'
      : 'Could not load the changelog from GitHub.';
  String get viewChangelog => isPt ? 'Ver changelog' : 'View changelog';
  String get close => isPt ? 'Fechar' : 'Close';
  String get checkingUpdates => isPt ? 'Verificando...' : 'Checking...';
  String get updateNotConfigured => isPt
      ? 'Fonte de atualização ainda não configurada.'
      : 'Update source is not configured yet.';
  String get noUpdatesAvailable => isPt
      ? 'Você já está na versão mais recente.'
      : 'You are already on the latest version.';
  String updateAvailable(String version) =>
      isPt ? 'Atualização disponível: $version' : 'Update available: $version';
  String get downloadAndInstall =>
      isPt ? 'Baixar e instalar' : 'Download and install';
  String get downloadingUpdate =>
      isPt ? 'Baixando atualização...' : 'Downloading update...';
  String get unknownSourcesNeeded => isPt
      ? 'Permita instalação por fontes desconhecidas para este app e toque em baixar novamente.'
      : 'Allow installs from unknown sources for this app, then tap download again.';
  String get updateCheckFailed =>
      isPt ? 'Falha ao verificar atualização.' : 'Failed to check for updates.';
  String get installUpdateFailed =>
      isPt ? 'Falha ao abrir instalador.' : 'Failed to open installer.';
  String get loadAchievementsFailed =>
      isPt ? 'Falha ao carregar conquistas' : 'Failed to load achievements';
  String get profileStats => isPt ? 'Estatísticas do perfil' : 'Profile stats';
  String get hideZeroPercentGames =>
      isPt ? 'Ocultar jogos com 0%' : 'Hide 0% games';
  String get hideZeroPercentGamesHelp => isPt
      ? 'Esconde jogos com conquistas, mas sem nenhuma conquista liberada.'
      : 'Hides games that have achievements but none unlocked.';
  String get knownAchievements =>
      isPt ? 'Conquistas conhecidas' : 'Known achievements';
  String get scannedGames => isPt ? 'Jogos escaneados' : 'Scanned games';
  String get scanNotice => isPt
      ? 'A atualização automática da tela principal roda enquanto o app está aberto. Para minimizar ou apagar a tela, use a sincronização manual com notificação.'
      : 'The home screen auto-update runs while the app is open. To minimize or turn the screen off, use manual sync with notification.';
  String get playtimeShort => isPt ? 'horas' : 'hours';
  String get syncProfileNow =>
      isPt ? 'Sincronizar perfil agora' : 'Sync profile now';
  String get syncStarted => isPt
      ? 'Sincronização iniciada. Você pode minimizar o app no celular e acompanhar pela notificação.'
      : 'Sync started. You can minimize the app on your phone and follow the notification.';
  String get notificationPermissionDenied => isPt
      ? 'A sincronização começou, mas a notificação pode não aparecer sem permissão.'
      : 'Sync started, but the notification may not appear without permission.';
  String get cachedDataShown => isPt
      ? 'Mostrando cache enquanto atualiza dados.'
      : 'Showing cached data while updating.';
  String scanProgress(int scanned, int total) => isPt
      ? '$scanned/$total jogos escaneados'
      : '$scanned/$total games scanned';
  String get totalPlaytime =>
      isPt ? 'Horas jogadas na Steam' : 'Steam playtime hours';
  String get completedGames => isPt ? 'Jogos completos' : 'Perfect games';
  String get perfectAchievements =>
      isPt ? 'Conquistas em jogos perfeitos' : 'Achievements in perfect games';
  String get totalAchievements =>
      isPt ? 'Total de conquistas' : 'Total achievements';
  String get totalGames => isPt ? 'Quantidade de jogos' : 'Total games';
  String get loadedGames =>
      isPt ? 'Jogos com progresso carregado' : 'Games with loaded progress';
  String get statsNote => isPt
      ? 'Horas e quantidade de jogos vêm direto da Steam API. Conquistas, jogos completos e perfeitos são calculados conforme o app analisa sua biblioteca.'
      : 'Playtime and game count come directly from the Steam API. Achievements, completed games, and perfect-game stats are calculated as the app scans your library.';
}
