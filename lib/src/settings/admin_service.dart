import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AppUserRole { member, admin, superadmin }

AppUserRole parseAppUserRole(Object? value) => switch (value?.toString()) {
  'admin' => AppUserRole.admin,
  'superadmin' => AppUserRole.superadmin,
  _ => AppUserRole.member,
};

extension AppUserRoleLabel on AppUserRole {
  String get databaseValue => switch (this) {
    AppUserRole.member => 'member',
    AppUserRole.admin => 'admin',
    AppUserRole.superadmin => 'superadmin',
  };

  String get label => switch (this) {
    AppUserRole.member => 'Member',
    AppUserRole.admin => 'Admin',
    AppUserRole.superadmin => 'Super Admin',
  };
}

class AdminUserInfo {
  const AdminUserInfo({
    required this.id,
    required this.email,
    required this.role,
    required this.aiEnabled,
    required this.requestsUsed,
    required this.requestsLimit,
    required this.tokensUsed,
    required this.tokensLimit,
    required this.fastRequestsUsed,
    required this.fastRequestsLimit,
  });

  factory AdminUserInfo.fromJson(Map<String, dynamic> json) => AdminUserInfo(
    id: json['user_id'].toString(),
    email: json['email']?.toString() ?? 'Email unavailable',
    role: parseAppUserRole(json['role']),
    aiEnabled: json['ai_enabled'] as bool? ?? true,
    requestsUsed: (json['request_count'] as num?)?.toInt() ?? 0,
    requestsLimit: (json['monthly_request_limit'] as num?)?.toInt() ?? 1000,
    tokensUsed: (json['tokens_used'] as num?)?.toInt() ?? 0,
    tokensLimit: (json['monthly_token_limit'] as num?)?.toInt() ?? 5000000,
    fastRequestsUsed: (json['fast_request_count'] as num?)?.toInt() ?? 0,
    fastRequestsLimit:
        (json['monthly_fast_request_limit'] as num?)?.toInt() ?? 100,
  );

  final String id;
  final String email;
  final AppUserRole role;
  final bool aiEnabled;
  final int requestsUsed;
  final int requestsLimit;
  final int tokensUsed;
  final int tokensLimit;
  final int fastRequestsUsed;
  final int fastRequestsLimit;

  double get requestsFraction =>
      requestsLimit <= 0 ? 0 : (requestsUsed / requestsLimit).clamp(0, 1);
  double get tokensFraction =>
      tokensLimit <= 0 ? 0 : (tokensUsed / tokensLimit).clamp(0, 1);
}

class AdminService {
  AdminService._();

  static final instance = AdminService._();
  final role = ValueNotifier<AppUserRole>(AppUserRole.member);
  final users = ValueNotifier<List<AdminUserInfo>?>(null);
  final isLoading = ValueNotifier<bool>(false);
  Future<void>? _preloading;
  bool _hasLoaded = false;
  String? _loadedUserId;

  Future<void> preload({bool force = false}) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (_hasLoaded && _loadedUserId == userId && !force) {
      return Future.value();
    }
    return _preloading ??= _load().whenComplete(() {
      _hasLoaded = true;
      _preloading = null;
    });
  }

  Future<void> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    _loadedUserId = userId;
    if (userId == null) {
      role.value = AppUserRole.member;
      users.value = null;
      return;
    }
    isLoading.value = true;
    try {
      final resolvedRole = await refreshRole();
      if (resolvedRole == AppUserRole.member) {
        users.value = null;
      } else {
        users.value = await _fetchUsers();
      }
    } finally {
      isLoading.value = false;
    }
  }

  Future<AppUserRole> refreshRole() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      return role.value = AppUserRole.member;
    }
    final value = await Supabase.instance.client.rpc('current_app_role');
    return role.value = parseAppUserRole(value);
  }

  Future<List<AdminUserInfo>> listUsers() async {
    isLoading.value = true;
    try {
      final loaded = await _fetchUsers();
      users.value = loaded;
      return loaded;
    } finally {
      isLoading.value = false;
    }
  }

  Future<List<AdminUserInfo>> _fetchUsers() async {
    final data = await Supabase.instance.client.rpc('admin_list_users');
    return (data as List)
        .map((row) => AdminUserInfo.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> updateUser(
    String userId, {
    bool? enabled,
    int? requestLimit,
    int? tokenLimit,
    int? fastRequestLimit,
    AppUserRole? role,
  }) async {
    await Supabase.instance.client.rpc(
      'admin_update_user',
      params: {
        'p_user_id': userId,
        'p_enabled': enabled,
        'p_monthly_request_limit': requestLimit,
        'p_monthly_token_limit': tokenLimit,
        'p_monthly_fast_request_limit': fastRequestLimit,
        'p_role': role?.databaseValue,
      },
    );
  }
}
