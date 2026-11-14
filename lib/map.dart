import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'login.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController mapController = MapController();
  StreamSubscription<Position>? positionStream;
  final List<Position> routePoints = [];
  bool isMeasuring = false;

  void showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------- POMIAR GPS ----------------

  Future<void> startMeasurement() async {
    if (isMeasuring) return;

    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      showMessage('Lokalizacja telefonu jest wyłączona');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      showMessage('Brak uprawnień do lokalizacji');
      return;
    }

    setState(() {
      routePoints.clear();
      isMeasuring = true;
    });

    final LocationSettings locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
    );

    bool firstPosition = true;

    positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) {
      if (!isMeasuring) return;
      setState(() {
        routePoints.add(position);
      });
      if (firstPosition) {
        mapController.move(LatLng(position.latitude, position.longitude), 17);
        firstPosition = false;
      }
    });

    showMessage('Pomiar rozpoczęty');
  }

  void stopMeasurement() {
    positionStream?.cancel();
    positionStream = null;
    setState(() {
      isMeasuring = false;
    });
    showMessage('Pomiar zakończony, zapisano punktów: ${routePoints.length}');
  }

  void resetMeasurement() {
    positionStream?.cancel();
    positionStream = null;
    setState(() {
      isMeasuring = false;
      routePoints.clear();
    });
    showMessage('Trasa została wyczyszczona');
  }

  // ---------------- ZAPIS I EKSPORT ----------------

  Future<void> saveMeasurement() async {
    if (routePoints.length < 2) {
      showMessage('Brak trasy do zapisania');
      return;
    }

    final geoJson = {
      'type': 'Feature',
      'properties': {
        'created_at': DateTime.now().toIso8601String(),
        'points_count': routePoints.length,
        'points': routePoints.map((p) {
          return {
            'latitude': p.latitude,
            'longitude': p.longitude,
            'timestamp': p.timestamp.toIso8601String(),
            'accuracy': p.accuracy,
            'altitude': p.altitude,
            'speed': p.speed,
          };
        }).toList(),
      },
      'geometry': {
        'type': 'LineString',
        'coordinates':
            routePoints.map((p) => [p.longitude, p.latitude]).toList(),
      },
    };

    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now()
          .toString()
          .replaceAll(':', '-')
          .replaceAll('.', '-')
          .replaceAll(' ', '_');
      final file = File('${directory.path}/trasa_$timestamp.geojson');
      await file.writeAsString(jsonEncode(geoJson));
      showMessage('Trasa została zapisana:\n${file.path}');
    } catch (e) {
      showMessage('Błąd zapisu: $e');
    }
  }

  Future<void> exportRoutes() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory
          .listSync()
          .whereType<File>()
          .where((file) {
            final name = file.path.split(Platform.pathSeparator).last;
            return name.startsWith('trasa_') && name.endsWith('.geojson');
          })
          .toList();

      if (files.isEmpty) {
        showMessage('Brak zapisanych tras do eksportu');
        return;
      }

      await SharePlus.instance.share(
        ShareParams(
          title: 'Eksport tras',
          text: 'Zapisane trasy marszu',
          files: files.map((file) => XFile(file.path)).toList(),
        ),
      );
    } catch (e) {
      showMessage('Błąd eksportu: $e');
    }
  }

  // ---------------- NAWIGACJA ----------------

  void logout() {
    positionStream?.cancel();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    positionStream?.cancel();
    super.dispose();
  }

  // ---------------- WIDOK ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WalkTracker'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            tooltip: 'Menu',
            onSelected: (value) {
              if (value == 'logout') {
                logout();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 30),
                    Text('Wyloguj'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: FlutterMap(
        mapController: mapController,
        options: const MapOptions(
          initialCenter: LatLng(52.23, 21.05),
          initialZoom: 12,
          minZoom: 5,
          maxZoom: 19,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.pamg_labs',
            maxZoom: 19,
          ),
          PolylineLayer(
            polylines: [
              if (routePoints.length >= 2)
                Polyline(
                  points: routePoints
                      .map((p) => LatLng(p.latitude, p.longitude))
                      .toList(),
                  strokeWidth: 5,
                  color: Colors.blue,
                ),
            ],
          ),
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('OpenStreetMap contributors'),
            ],
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: Icon(
                Icons.play_arrow,
                color: isMeasuring ? Colors.green : null,
              ),
              tooltip: 'Rozpocznij pomiar',
              onPressed: startMeasurement,
            ),
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: 'Zakończ pomiar',
              onPressed: stopMeasurement,
            ),
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Zapisz pomiar',
              onPressed: saveMeasurement,
            ),
            IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: 'Eksportuj trasy',
              onPressed: exportRoutes,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Resetuj pomiar',
              onPressed: resetMeasurement,
            ),
            IconButton(
              icon: const Icon(Icons.analytics),
              tooltip: 'Wyniki',
              onPressed: () => showMessage('Strona w tworzeniu'),
            ),
          ],
        ),
      ),
    );
  }
}