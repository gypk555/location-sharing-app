class SosSettings {
  final bool shakeAlertEnabled;
  final String? sosMessage;

  const SosSettings({
    this.shakeAlertEnabled = true,
    this.sosMessage,
  });

  factory SosSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SosSettings();
    
    // Parse boolean defensively
    bool shakeAlertEnabled = true;
    if (json['shakeAlertEnabled'] is bool) {
      shakeAlertEnabled = json['shakeAlertEnabled'] as bool;
    }

    // Parse message defensively
    String? sosMessage;
    if (json['sosMessage'] is String) {
      sosMessage = json['sosMessage'] as String;
    }

    return SosSettings(
      shakeAlertEnabled: shakeAlertEnabled,
      sosMessage: sosMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shakeAlertEnabled': shakeAlertEnabled,
      'sosMessage': sosMessage,
    };
  }

  // Returns error string if invalid, null if valid
  String? validate() {
    if (sosMessage != null) {
      if (sosMessage!.isEmpty) {
        return 'SOS message cannot be empty';
      }
      if (sosMessage!.length > 500) {
        return 'SOS message cannot exceed 500 characters';
      }
      if (!sosMessage!.contains('{location}')) {
        return 'SOS message must contain {location} placeholder';
      }
    }
    return null;
  }

  // Sentinel to distinguish "not provided" from "explicitly null"
  static const _unset = Object();

  SosSettings copyWith({
    bool? shakeAlertEnabled,
    Object? sosMessage = _unset, // use Object? so null can be passed explicitly
  }) {
    return SosSettings(
      shakeAlertEnabled: shakeAlertEnabled ?? this.shakeAlertEnabled,
      sosMessage: sosMessage == _unset ? this.sosMessage : sosMessage as String?,
    );
  }
}

class FakeCallSettings {
  final bool enabled;
  final String callerName;
  final String callerNumber;

  const FakeCallSettings({
    this.enabled = true,
    this.callerName = 'Mom',
    this.callerNumber = '+12345678900',
  });

  factory FakeCallSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FakeCallSettings();

    // Parse bool defensively
    bool enabled = true;
    if (json['enabled'] is bool) {
      enabled = json['enabled'] as bool;
    }

    // Parse strings defensively
    String callerName = 'Mom';
    if (json['callerName'] is String) {
      callerName = json['callerName'] as String;
    }

    String callerNumber = '+12345678900';
    if (json['callerNumber'] is String) {
      callerNumber = json['callerNumber'] as String;
    }

    return FakeCallSettings(
      enabled: enabled,
      callerName: callerName,
      callerNumber: callerNumber,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'callerName': callerName,
      'callerNumber': callerNumber,
    };
  }

  // Returns error string if invalid, null if valid
  String? validate() {
    if (callerName.isEmpty) {
      return 'Caller name cannot be empty';
    }
    if (callerName.length > 50) {
      return 'Caller name cannot exceed 50 characters';
    }
    // Basic emoji/control char check can be added here if needed

    if (callerNumber.isEmpty) {
      return 'Caller number cannot be empty';
    }
    // E.164 format validation: starts with +, followed by 1-14 digits
    final RegExp phoneExp = RegExp(r'^\+[1-9]\d{1,14}$');
    if (!phoneExp.hasMatch(callerNumber)) {
      return 'Invalid phone number format (must be E.164, e.g. +1234567890)';
    }

    return null;
  }

  FakeCallSettings copyWith({
    bool? enabled,
    String? callerName,
    String? callerNumber,
  }) {
    return FakeCallSettings(
      enabled: enabled ?? this.enabled,
      callerName: callerName ?? this.callerName,
      callerNumber: callerNumber ?? this.callerNumber,
    );
  }
}
