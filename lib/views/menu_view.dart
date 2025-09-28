import 'package:flutter/material.dart';
import 'package:safestep/views/fake_call_view.dart';
import 'package:safestep/views/close_contacts_view.dart';
import 'package:safestep/views/safe_chat_view.dart';
import 'package:safestep/views/report_danger_zone_view.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// --- Primary Theme Colors (Refined for Elegance & Clarity) ---
const Color _lightViolet = Color(0xFFD1C4E9);       // Soft violet background mid-tone
const Color _cardSurface = Colors.white;            // Crisp white card background
const Color _darkText = Color(0xFF232946);          // Dark, readable text

class MenuView extends StatefulWidget {
  final ValueChanged<bool>? onFeatureOpen;
  final void Function(LatLng, double)? onAddDangerZone;
  final LatLng? currentPosition;
  final VoidCallback? onNavigateToMap;
  const MenuView({super.key, this.onFeatureOpen, this.onAddDangerZone, this.currentPosition, this.onNavigateToMap});

  @override
  State<MenuView> createState() => _MenuViewState();
}

class _MenuViewState extends State<MenuView> with TickerProviderStateMixin {
  Widget? _selectedFeature;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _openFeature(Widget feature) {
    setState(() {
      _selectedFeature = feature;
    });
    widget.onFeatureOpen?.call(true);
  }

  void _closeFeature() {
    setState(() {
      _selectedFeature = null;
    });
    widget.onFeatureOpen?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedFeature != null) {
      return _selectedFeature!;
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          // THEME BACKGROUND: Soft violet gradient
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFB39DDB),
                _lightViolet,
                Color(0xFFF8F9FF),
              ],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                // --- SafeStep Logo Header ---
                Positioned(
                  top: -2,
                  left: 20,
                  right: 20,
                  child: Center(
                    child: Image.asset(
                      'assets/safestep_text.png',
                      height: 120,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Text(
                          'SafeStep',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF8F5FE8),
                            letterSpacing: -1.0,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                
                // --- Content with tiles overlapping image ---
                Positioned(
                  top: 108,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: CustomScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    slivers: [
                      // --- Feature Grid ---
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.9,
                       crossAxisSpacing: 12,
                       mainAxisSpacing: 8,
                    ),
                    delegate: SliverChildListDelegate([
                      _ElegantMenuCard(
                        icon: Icons.call_end,
                        label: 'Fake Call',
                        subtitle: 'Simulate a call to exit a situation.',
                        iconColor: const Color(0xFF667eea), // Call Gradient Start
                        onTap: () => _openFeature(FakeCallView(onBack: _closeFeature)),
                      ),
                      _ElegantMenuCard(
                        icon: Icons.warning_amber_rounded,
                        label: 'Report Danger',
                        subtitle: 'Mark unsafe areas on map.',
                        iconColor: const Color(0xFFf093fb), // Report Gradient Start
                        onTap: () => _openFeature(ReportDangerZoneView(
                          currentPosition: widget.currentPosition,
                          onDangerZoneChanged: widget.onAddDangerZone,
                          onBack: _closeFeature,
                        )),
                      ),
                    ]),
                  ),
                ),

                      // --- Secondary Grid ---
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.9,
                       crossAxisSpacing: 12,
                       mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildListDelegate([
                      _ElegantMenuCard(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'SafeChat AI',
                        subtitle: 'AI-powered chat for your safety.',
                        iconColor: const Color(0xFF4facfe), // Chat Gradient Start
                        onTap: () => _openFeature(const SafeChatView()),
                      ),
                      _ElegantMenuCard(
                        icon: Icons.people_alt_outlined,
                        label: 'Close Contacts',
                        subtitle: 'Manage and share your location.',
                        iconColor: const Color(0xFF43e97b), // Contacts Gradient Start
                        onTap: () => _openFeature(CloseContactsView(onBack: _closeFeature)),
                      ),
                    ]),
                  ),
                ),

                      // --- Safety Map Tile (2x1.5) ---
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                     child: Container(
                       height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: _cardSurface,
                        border: Border.all(color: Colors.grey.shade100, width: 1.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                          BoxShadow(
                            color: const Color(0xFF8F5FE8).withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: -12,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            // Navigate to map view
                            widget.onNavigateToMap?.call();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF8F5FE8).withOpacity(0.15),
                                    border: Border.all(
                                      color: const Color(0xFF8F5FE8).withOpacity(0.4),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.map_rounded,
                                    color: Color(0xFF8F5FE8),
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Safety Map',
                                        style: TextStyle(
                                          color: _darkText,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'View and share your location, stay clear of unsafe areas.',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios,
                                  color: Color(0xFF8F5FE8),
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                      // Bottom spacing
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 100),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- The "Elegance & Clarity" User-Friendly Card Widget ---
class _ElegantMenuCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color iconColor; // Single accent color for simplicity
  final VoidCallback onTap;

  const _ElegantMenuCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.iconColor,
    required this.onTap,
  });

  @override
  State<_ElegantMenuCard> createState() => _ElegantMenuCardState();
}

class _ElegantMenuCardState extends State<_ElegantMenuCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _shadowElevation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    // Subtle press-in animation
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    // Shadow lift animation
    _shadowElevation = Tween<double>(begin: 12.0, end: 3.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            // ELEGANCE & CLARITY DESIGN: Crisp white card body
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: _cardSurface, 
              border: Border.all(color: Colors.grey.shade100, width: 1.0),
              boxShadow: [
                // Soft, clean lift shadow
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: _shadowElevation.value,
                  offset: const Offset(0, 5),
                ),
                // Subtle colored inner glow/ring (WOW factor)
                BoxShadow(
                  color: widget.iconColor.withOpacity(0.4),
                  blurRadius: 20, 
                  spreadRadius: -12,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: widget.onTap,
                onTapDown: (_) => _controller.forward(),
                onTapUp: (_) => _controller.reverse(),
                onTapCancel: () => _controller.reverse(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ICON: Vibrant, highly focused icon ring
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.iconColor.withOpacity(0.15),
                          border: Border.all(color: widget.iconColor.withOpacity(0.4), width: 1.5),
                        ),
                        child: Icon(
                          widget.icon,
                          color: widget.iconColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Text content (Optimal Readability)
                      Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _darkText,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}