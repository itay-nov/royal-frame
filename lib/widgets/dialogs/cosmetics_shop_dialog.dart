import 'package:flutter/material.dart';

import '../../services/xp_service.dart';
import '../../theme_constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COSMETICS SHOP DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class CosmeticsShopDialog extends StatefulWidget {
  final VoidCallback onChanged;
  const CosmeticsShopDialog({super.key, required this.onChanged});

  @override
  State<CosmeticsShopDialog> createState() =>
      _CosmeticsShopDialogState();
}

class _CosmeticsShopDialogState extends State<CosmeticsShopDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: kBurgundyDeep,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kGold, width: 1.8),
          boxShadow: [
            BoxShadow(
                color: kGold.withValues(alpha: 0.15),
                blurRadius: 32,
                spreadRadius: 2),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding:
                  const EdgeInsets.fromLTRB(20, 18, 16, 0),
              decoration: BoxDecoration(
                color: kBurgundyLight.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.style,
                          color: kGold, size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Theme Gallery',
                          style: TextStyle(
                            color: kGold,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      // XP / level display
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius:
                              BorderRadius.circular(12),
                          border: Border.all(
                              color:
                                  kGoldDark.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star,
                                color: kGold, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              'Lv.${XpService.playerLevel}  '
                              '${XpService.xpInCurrentLevel}/${XpService.xpPerLevel} XP',
                              style: const TextStyle(
                                  color: kGoldLight,
                                  fontSize: 11,
                                  fontWeight:
                                      FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius:
                            BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close,
                              color: kGoldDark, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TabBar(
                    controller: _tabCtrl,
                    indicatorColor: kGold,
                    labelColor: kGold,
                    unselectedLabelColor: kGoldDark,
                    tabs: const [
                      Tab(text: 'Card Backs'),
                      Tab(text: 'Board Colors'),
                    ],
                  ),
                ],
              ),
            ),

            // Tab content
            SizedBox(
              height: 320,
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildItemGrid(XpService.cardBacks,
                      isCardBack: true),
                  _buildItemGrid(XpService.boardColors,
                      isCardBack: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemGrid(List<CosmeticItem> items,
      {required bool isCardBack}) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.75,
      ),
      itemCount: items.length,
      itemBuilder: (context, idx) {
        final item = items[idx];
        final isUnlocked = isCardBack
            ? XpService.isBackUnlocked(item.id)
            : XpService.isColorUnlocked(item.id);
        final isEquipped = isCardBack
            ? XpService.equippedBackId == item.id
            : XpService.equippedColorId == item.id;

        return GestureDetector(
          onTap: isUnlocked
              ? () async {
                  if (isCardBack) {
                    await XpService.equipCardBack(item.id);
                  } else {
                    await XpService.equipBoardColor(item.id);
                  }
                  setState(() {});
                  widget.onChanged();
                }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isEquipped
                    ? kGold
                    : (isUnlocked
                        ? Colors.white24
                        : Colors.white10),
                width: isEquipped ? 2.5 : 1.2,
              ),
              boxShadow: isEquipped
                  ? [
                      BoxShadow(
                          color: kGold.withValues(alpha: 0.3),
                          blurRadius: 8)
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Preview
                  isCardBack
                      ? (item.assetPath != null
                          ? Image.asset(
                              item.assetPath!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  ColoredBox(
                                color: item.fallbackColor ??
                                    kCardRed,
                              ),
                            )
                          : ColoredBox(
                              color: item.fallbackColor ??
                                  kCardRed))
                      : ColoredBox(
                          color: item.boardColor ?? kBurgundy),

                  // Lock overlay
                  if (!isUnlocked)
                    Container(
                      color: Colors.black.withValues(alpha: 0.65),
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock,
                              color: Colors.white54, size: 22),
                          const SizedBox(height: 4),
                          Text(
                            'Lv.${item.levelRequired}',
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),

                  // Equipped checkmark
                  if (isEquipped)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                            color: kGold,
                            shape: BoxShape.circle),
                        child: const Icon(Icons.check,
                            color: Colors.black, size: 12),
                      ),
                    ),

                  // Name label
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 4),
                      color: Colors.black.withValues(alpha: 0.55),
                      child: Text(
                        item.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isEquipped
                              ? kGold
                              : Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

