import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum NetworkReachabilityStatus { unknown, online, offline }

class NetworkReachabilityService {
  NetworkReachabilityService._();

  static final NetworkReachabilityService instance =
      NetworkReachabilityService._();

  final ValueNotifier<NetworkReachabilityStatus> status =
      ValueNotifier<NetworkReachabilityStatus>(
        NetworkReachabilityStatus.unknown,
      );

  Timer? _pollTimer;
  Future<NetworkReachabilityStatus>? _activeProbe;
  bool _keepAlive = false;

  bool get isOnline => status.value == NetworkReachabilityStatus.online;
  bool get isOffline => status.value == NetworkReachabilityStatus.offline;

  void start({bool keepAlive = false}) {
    _keepAlive = _keepAlive || keepAlive;
    _pollTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(refresh());
    });
    unawaited(refresh());
  }

  void stop() {
    if (_keepAlive) return;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<NetworkReachabilityStatus> refresh() {
    final activeProbe = _activeProbe;
    if (activeProbe != null) return activeProbe;

    final probe = _probe()
        .then((nextStatus) {
          if (status.value != nextStatus) {
            status.value = nextStatus;
          }
          return nextStatus;
        })
        .whenComplete(() {
          _activeProbe = null;
        });

    _activeProbe = probe;
    return probe;
  }

  Future<bool> waitUntilOnline({
    Duration probeInterval = const Duration(seconds: 2),
    Duration? timeout,
  }) async {
    final deadline = timeout == null ? null : DateTime.now().add(timeout);

    while (true) {
      if (await refresh() == NetworkReachabilityStatus.online) {
        return true;
      }

      if (deadline != null && DateTime.now().isAfter(deadline)) {
        return false;
      }

      await Future<void>.delayed(probeInterval);
    }
  }

  Future<NetworkReachabilityStatus> _probe() async {
    if (kIsWeb) return NetworkReachabilityStatus.unknown;

    final tcpOk =
        await _canOpenSocket('1.1.1.1', 443) ||
        await _canOpenSocket('8.8.8.8', 443);
    if (tcpOk) return NetworkReachabilityStatus.online;

    final dnsOk = await _canResolveHost('example.com');
    return dnsOk
        ? NetworkReachabilityStatus.online
        : NetworkReachabilityStatus.offline;
  }

  Future<bool> _canOpenSocket(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _canResolveHost(String host) async {
    try {
      final addresses = await InternetAddress.lookup(
        host,
      ).timeout(const Duration(seconds: 3));
      return addresses.any((address) => address.rawAddress.isNotEmpty);
    } catch (_) {
      return false;
    }
  }
}
