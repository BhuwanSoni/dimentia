import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class EmergencyReceiverPage extends StatefulWidget {
  /// The UID of the patient being monitored.
  /// Pass this from the family member's account after they link to a patient.
  /// If null, falls back to the current user's own UID (useful during testing).
  final String? patientUserId;

  const EmergencyReceiverPage({super.key, this.patientUserId});

  @override
  State<EmergencyReceiverPage> createState() => _EmergencyReceiverPageState();
}

class _EmergencyReceiverPageState extends State<EmergencyReceiverPage> {
  StreamSubscription<QuerySnapshot>? _alertSubscription;

  /// IDs of alerts already seen — prevents the popup firing for old docs
  /// that Firestore sends on first connection.
  final Set<String> _seenIds = {};
  bool _initialLoadDone = false;

  String get _watchedUid =>
      widget.patientUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    super.dispose();
  }

  void _startListening() {
    final stream = FirebaseFirestore.instance
        .collection('emergencies')
        .where('userId', isEqualTo: _watchedUid)
        .orderBy('timestamp', descending: true)
        .snapshots();

    _alertSubscription = stream.listen((snapshot) {
      // Mark all docs from the very first snapshot as "already seen"
      // so we only popup for NEW additions after the page opens.
      if (!_initialLoadDone) {
        for (final doc in snapshot.docs) {
          _seenIds.add(doc.id);
        }
        _initialLoadDone = true;
        return;
      }

      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added &&
            !_seenIds.contains(change.doc.id)) {
          _seenIds.add(change.doc.id);
          final location =
              (change.doc.data() as Map<String, dynamic>)['location']
                  as String? ??
                  '';
          _showAlertDialog(location);
        }
      }
    }, onError: (e) {
      debugPrint("Emergency listener error: $e");
    });
  }

  void _showAlertDialog(String location) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.red.shade50,
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text(
              "EMERGENCY",
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Your family member needs help!",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (location.startsWith("http"))
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.map_rounded),
                  label: const Text("Open Location on Map"),
                  onPressed: () => _openLocation(location),
                ),
              )
            else
              Text(
                "⚠️ Location not available",
                style: TextStyle(color: Colors.grey.shade600),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Dismiss"),
          ),
        ],
      ),
    );
  }

  Future<void> _openLocation(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return "Unknown time";
    final dt = ts.toDate().toLocal();
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return "$day/$month/${dt.year}  $hour:$minute $ampm";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text(
          "🚨 Emergency Alerts",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.red.shade700,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('emergencies')
            .where('userId', isEqualTo: _watchedUid)
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          // ── Loading ──────────────────────────────────────────────────────
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // ── Error ────────────────────────────────────────────────────────
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        size: 56, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(
                      "Could not connect to alerts.\nCheck your internet connection.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            );
          }

          // ── Empty ────────────────────────────────────────────────────────
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline_rounded,
                      size: 72, color: Colors.green.shade300),
                  const SizedBox(height: 16),
                  Text(
                    "No emergencies",
                    style: TextStyle(
                        fontSize: 18, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "All clear ✅",
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                ],
              ),
            );
          }

          // ── List ─────────────────────────────────────────────────────────
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final location = data['location'] as String? ?? '';
              final timestamp = data['timestamp'] as Timestamp?;
              final isFirst = index == 0;

              return Card(
                color: isFirst ? Colors.red.shade50 : Colors.white,
                elevation: isFirst ? 3 : 1,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isFirst
                        ? Colors.red.shade200
                        : Colors.grey.shade200,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header row ──────────────────────────────────────
                      Row(
                        children: [
                          Icon(
                            Icons.warning_rounded,
                            color:
                                isFirst ? Colors.red : Colors.orange.shade400,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isFirst ? "🚨 LATEST EMERGENCY" : "Emergency",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: isFirst ? 15 : 14,
                              color: isFirst
                                  ? Colors.red.shade700
                                  : Colors.orange.shade800,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatTimestamp(timestamp),
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // ── Location row ────────────────────────────────────
                      if (location.startsWith("http"))
                        GestureDetector(
                          onTap: () => _openLocation(location),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.location_on_rounded,
                                    color: Colors.blue, size: 18),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    "Tap to open location on map",
                                    style: TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.open_in_new_rounded,
                                    color: Colors.blue, size: 16),
                              ],
                            ),
                          ),
                        )
                      else
                        Text(
                          "⚠️ Location not available",
                          style:
                              TextStyle(color: Colors.grey.shade500),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}