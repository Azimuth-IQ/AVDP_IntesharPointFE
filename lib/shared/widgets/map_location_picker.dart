import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:inteshar/app/theme.dart';
import 'package:latlong2/latlong.dart';

/// Approximate geographic centre of Iraq (near Baghdad) — the default map focus
/// when an entity has no location yet.
const LatLng _iraqCentre = LatLng(33.3152, 44.3661);

/// Open a full-screen OpenStreetMap picker and return the chosen point, or null
/// if cancelled. Tap anywhere on the map to drop/move the pin (B-037 — pick a
/// location on a map instead of typing raw latitude/longitude).
Future<LatLng?> pickLocationOnMap(BuildContext context, {LatLng? initial}) {
  return Navigator.of(context).push<LatLng>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _MapLocationPicker(initial: initial),
    ),
  );
}

class _MapLocationPicker extends StatefulWidget {
  final LatLng? initial;
  const _MapLocationPicker({this.initial});

  @override
  State<_MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<_MapLocationPicker> {
  late final MapController _controller = MapController();
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    final picked = _picked;
    return Scaffold(
      appBar: AppBar(
        title: Text(ar ? 'اختر الموقع' : 'Pick location'),
        actions: [
          TextButton(
            onPressed: picked == null ? null : () => Navigator.pop(context, picked),
            child: Text(
              ar ? 'تأكيد' : 'Confirm',
              style: TextStyle(
                // UX-138: `cs.primary` is the brand FILL. Used as ink on the
                // white app bar it is raw gold at ~2:1 — the enabled Confirm
                // read as fainter than the disabled one. `brandOnSurface` is
                // the measured ≥4.5:1 brand ink.
                color: picked == null
                    ? cs.onSurfaceVariant
                    : context.tones.brandOnSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: picked ?? _iraqCentre,
              initialZoom: picked != null ? 15 : 6,
              onTap: (_, point) => setState(() => _picked = point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.azimuthiraq.inteshar',
              ),
              if (picked != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: picked,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: Icon(Icons.location_on, size: 44, color: cs.error),
                    ),
                  ],
                ),
            ],
          ),
          // Instruction / read-out banner.
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              color: cs.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: IntesharSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.touch_app_outlined, size: 20, color: cs.onSurfaceVariant),
                    const SizedBox(width: IntesharSpacing.sm2),
                    Expanded(
                      child: Text(
                        picked == null
                            ? (ar ? 'انقر على الخريطة لتحديد الموقع' : 'Tap the map to set the location')
                            : '${picked.latitude.toStringAsFixed(6)}, ${picked.longitude.toStringAsFixed(6)}',
                        style: TextStyle(color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
