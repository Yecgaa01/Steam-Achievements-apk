import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_text.dart';
import '../models/steam_models.dart';

class AchievementTile extends StatefulWidget {
  final SteamAchievement achievement;
  final AppText text;
  final bool revealHiddenByDefault;
  final bool showRarityTier;

  const AchievementTile({super.key, required this.achievement, required this.text, this.revealHiddenByDefault = false, this.showRarityTier = true});

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
    if (!widget.showRarityTier || percent == null) return null;
    if (percent < 1) return widget.text.rarityMythic;
    if (percent < 5) return widget.text.rarityLegendary;
    if (percent < 10) return widget.text.rarityVeryRare;
    if (percent < 20) return widget.text.rarityRare;
    if (percent < 50) return widget.text.rarityUncommon;
    return widget.text.rarityCommon;
  }

  Color? _rarityTierColor(double? percent) {
    if (!widget.showRarityTier || percent == null) return null;
    if (percent < 1) return const Color(0xFFFB7185);
    if (percent < 5) return const Color(0xFFFACC15);
    if (percent < 10) return const Color(0xFFC084FC);
    if (percent < 20) return const Color(0xFF60A5FA);
    if (percent < 50) return const Color(0xFF86EFAC);
    return const Color(0xFF93C5FD);
  }
  @override
  Widget build(BuildContext context) {
    final achievement = widget.achievement;
    final text = widget.text;
    final iconUrl = achievement.achieved ? achievement.icon : achievement.iconGray;
    final percent = achievement.globalPercent == null ? '' : '${achievement.globalPercent!.toStringAsFixed(1)}%';
    final rarityTier = _rarityTier(achievement.globalPercent);
    final rarityTierColor = _rarityTierColor(achievement.globalPercent);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tileColor = achievement.achieved ? (dark ? const Color(0xFF102A43) : const Color(0xFFE0F2FE)) : (dark ? const Color(0xFF111827) : Colors.white);
    final borderColor = achievement.achieved ? const Color(0xFF38BDF8) : (dark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0));
    final subtleText = dark ? Colors.white60 : const Color(0xFF64748B);
    final statusText = achievement.achieved ? const Color(0xFF0284C7) : (dark ? Colors.white54 : const Color(0xFF64748B));
    final placeholderColor = dark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0);
    final placeholderIconColor = dark ? Colors.white54 : const Color(0xFF64748B);
    final shouldHideDetails = achievement.hidden && !widget.revealHiddenByDefault && !_revealed;
    final description = shouldHideDetails
        ? text.hiddenAchievement
        : (achievement.description.isEmpty ? text.hiddenDescriptionUnavailable : achievement.description);
    final title = shouldHideDetails ? text.hiddenAchievement : achievement.name;

    return InkWell(
      onTap: achievement.hidden ? () => setState(() => _revealed = !_revealed) : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: tileColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: iconUrl,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 52,
                  height: 52,
                  color: placeholderColor,
                  child: Icon(achievement.hidden ? Icons.visibility_off : Icons.emoji_events, color: placeholderIconColor),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                      if (achievement.hidden) const Icon(Icons.visibility_off, size: 16, color: Colors.amber),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: subtleText, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 7,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(achievement.achieved ? text.released : text.notReleased, style: TextStyle(color: statusText, fontSize: 12)),
                      if (rarityTier != null && rarityTierColor != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: rarityTierColor.withValues(alpha: dark ? 0.14 : 0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: rarityTierColor.withValues(alpha: 0.75)),
                          ),
                          child: Text(rarityTier, style: TextStyle(color: rarityTierColor, fontSize: 11, fontWeight: FontWeight.w900)),
                        ),
                      if (percent.isNotEmpty) Text(percent, style: TextStyle(color: subtleText, fontSize: 12, fontWeight: FontWeight.w700)),
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
