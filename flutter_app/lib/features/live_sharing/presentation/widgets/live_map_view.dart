import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../shared/constants/app_constants.dart';
import '../../../../shared/theme/app_theme.dart';

/// Reusable OpenStreetMap-backed map widget used by both the sharer's
/// active-share screen and the receiver's in-app view. Backed by
/// `flutter_map` + OSM tiles — no API key or billing required.
///
/// Renders:
///   - A marker at the target point (rotated by [headingDegrees])
///   - A translucent accuracy circle sized by [accuracyMeters]
///   - A "Stale" badge if [lastUpdated] is older than [kStaleThreshold]
///   - An "ended" overlay when [ended] is true
///   - A recenter FAB that reappears once the user has manually panned
class LiveMapView extends StatefulWidget {
  const LiveMapView({
    super.key,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.headingDegrees,
    this.lastUpdated,
    this.label,
    this.ended = false,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? headingDegrees;
  final DateTime? lastUpdated;
  final String? label;
  final bool ended;

  @override
  State<LiveMapView> createState() => _LiveMapViewState();
}

class _LiveMapViewState extends State<LiveMapView> {
  final MapController _controller = MapController();
  bool _userPanned = false;
  bool _mapReady = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LiveMapView old) {
    super.didUpdateWidget(old);
    if (!_userPanned &&
        _mapReady &&
        (old.latitude != widget.latitude ||
            old.longitude != widget.longitude)) {
      _recenter();
    }
  }

  void _recenter() {
    if (!_mapReady) return;
    _controller.move(
      LatLng(widget.latitude, widget.longitude),
      _controller.camera.zoom,
    );
  }

  bool get _isStale {
    final ts = widget.lastUpdated;
    if (ts == null) return false;
    return DateTime.now().difference(ts) > AppConstants.kStaleThreshold;
  }

  @override
  Widget build(BuildContext context) {
    final target = LatLng(widget.latitude, widget.longitude);

    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: target,
            initialZoom: 16,
            minZoom: 3,
            maxZoom: 19,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.drag |
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.flingAnimation,
            ),
            onMapReady: () {
              _mapReady = true;
            },
            onPositionChanged: (position, hasGesture) {
              // Only flip to user-panned when the gesture came from the
              // user. Programmatic moves (our recenter) don't set this.
              if (hasGesture && !_userPanned) {
                setState(() => _userPanned = true);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.safetyapp.safety_app',
              maxZoom: 19,
            ),
            if (widget.accuracyMeters != null && widget.accuracyMeters! > 0)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: target,
                    radius: widget.accuracyMeters!,
                    useRadiusInMeter: true,
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    borderColor:
                        AppTheme.primaryColor.withValues(alpha: 0.45),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  point: target,
                  width: 56,
                  height: 56,
                  alignment: Alignment.topCenter,
                  child: _LiveMarker(
                    label: widget.label,
                    headingDegrees: widget.headingDegrees,
                  ),
                ),
              ],
            ),
            const _OsmAttribution(),
          ],
        ),
        if (_isStale && !widget.ended)
          const Positioned(
            top: 12,
            left: 12,
            child: _Badge(
              color: Colors.orange,
              icon: Icons.access_time_filled,
              text: 'Stale',
            ),
          ),
        if (widget.ended)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.45),
              alignment: Alignment.center,
              child: const _Badge(
                color: Colors.black87,
                icon: Icons.stop_circle,
                text: 'Sharing ended',
              ),
            ),
          ),
        if (_userPanned)
          Positioned(
            bottom: 12,
            right: 12,
            child: FloatingActionButton.small(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              onPressed: () {
                setState(() => _userPanned = false);
                _recenter();
              },
              child: const Icon(Icons.my_location),
            ),
          ),
      ],
    );
  }
}

/// The live marker: a colored pin with an optional label. If heading is
/// provided (GPS course in degrees), the pin rotates to match.
class _LiveMarker extends StatelessWidget {
  const _LiveMarker({this.label, this.headingDegrees});
  final String? label;
  final double? headingDegrees;

  @override
  Widget build(BuildContext context) {
    const pin = Icon(
      Icons.navigation,
      color: AppTheme.primaryColor,
      size: 36,
      shadows: [Shadow(blurRadius: 6, color: Colors.black38)],
    );
    final rotated = headingDegrees == null
        ? const Icon(
            Icons.location_pin,
            color: AppTheme.primaryColor,
            size: 40,
            shadows: [Shadow(blurRadius: 6, color: Colors.black38)],
          )
        : Transform.rotate(
            angle: headingDegrees! * math.pi / 180,
            child: pin,
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        rotated,
        if (label != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(blurRadius: 2, color: Colors.black26),
              ],
            ),
            child: Text(
              label!,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

/// OSM requires visible attribution. Placed as a small chip in the
/// bottom-left corner; tapping would open the contributors page but we
/// keep it non-interactive here to avoid a url_launcher dependency loop.
class _OsmAttribution extends StatelessWidget {
  const _OsmAttribution();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          color: Colors.white.withValues(alpha: 0.85),
          child: const Text(
            '© OpenStreetMap',
            style: TextStyle(fontSize: 9, color: Colors.black87),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.icon, required this.text});
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
