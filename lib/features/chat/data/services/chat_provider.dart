import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:budget_ai/features/chat/domain/models/ai_models.dart';
import 'package:budget_ai/features/chat/domain/chat_model_config.dart';
import 'package:budget_ai/tools/tools.dart';
import 'package:budget_ai/features/settings/data/api_key_storage_service.dart';
import 'package:budget_ai/core/storage/shared_prefs_service.dart';
import 'package:budget_ai/tools/settings/tool_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

part 'chat_provider_helpers.dart';
part 'chat_message_models.dart';
part 'chat_system_prompt.dart';
part 'chat_provider_clients.dart';
