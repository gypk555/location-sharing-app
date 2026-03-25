import React, {useState, useCallback, useRef} from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Alert,
  Vibration,
  Animated,
} from 'react-native';
import {useNavigation} from '@react-navigation/native';
import {useLocation} from '../../modules/location/LocationContext';
import {sendSosAlert} from '../../modules/sms/smsService';
import AsyncStorage from '@react-native-async-storage/async-storage';

const EMERGENCY_CONTACTS_KEY = '@emergency_contacts';
const SOS_HOLD_DURATION = 3000; // 3 seconds
const SOS_COOLDOWN_MS = 60000; // 1 minute

interface EmergencyContact {
  id: string;
  name: string;
  phone: string;
}

export default function SosScreen() {
  const navigation = useNavigation();
  const {getCurrentPosition} = useLocation();

  const [isHolding, setIsHolding] = useState(false);
  const [isSending, setIsSending] = useState(false);
  const [lastSosTime, setLastSosTime] = useState<number | null>(null);

  const holdProgress = useRef(new Animated.Value(0)).current;
  const holdTimeout = useRef<NodeJS.Timeout | null>(null);

  const handlePressIn = () => {
    // Check cooldown
    if (lastSosTime && Date.now() - lastSosTime < SOS_COOLDOWN_MS) {
      const waitSeconds = Math.ceil(
        (SOS_COOLDOWN_MS - (Date.now() - lastSosTime)) / 1000,
      );
      Alert.alert(
        'Please Wait',
        `You can send another SOS in ${waitSeconds} seconds`,
      );
      return;
    }

    setIsHolding(true);
    Vibration.vibrate(100);

    // Start progress animation
    Animated.timing(holdProgress, {
      toValue: 1,
      duration: SOS_HOLD_DURATION,
      useNativeDriver: false,
    }).start();

    // Set timeout to trigger SOS
    holdTimeout.current = setTimeout(() => {
      triggerSos();
    }, SOS_HOLD_DURATION);
  };

  const handlePressOut = () => {
    if (holdTimeout.current) {
      clearTimeout(holdTimeout.current);
      holdTimeout.current = null;
    }

    setIsHolding(false);
    holdProgress.setValue(0);
  };

  const triggerSos = useCallback(async () => {
    setIsHolding(false);
    setIsSending(true);

    // Haptic feedback
    Vibration.vibrate([0, 200, 100, 200, 100, 200]);

    try {
      // Get emergency contacts
      const contactsStr = await AsyncStorage.getItem(EMERGENCY_CONTACTS_KEY);
      const contacts: EmergencyContact[] = contactsStr
        ? JSON.parse(contactsStr)
        : [];

      if (contacts.length === 0) {
        Alert.alert(
          'No Emergency Contacts',
          'Please add emergency contacts in Settings first.',
          [
            {text: 'Cancel', style: 'cancel'},
            {
              text: 'Add Contacts',
              onPress: () => navigation.navigate('EmergencyContacts' as never),
            },
          ],
        );
        setIsSending(false);
        return;
      }

      // Get current location
      const location = await getCurrentPosition();

      // Send SOS
      const result = await sendSosAlert(
        location,
        contacts.map(c => ({phone: c.phone, name: c.name})),
      );

      setLastSosTime(Date.now());

      if (result.success) {
        Alert.alert(
          'SOS Sent',
          `Emergency alert sent to ${contacts.length} contact(s).`,
          [{text: 'OK', onPress: () => navigation.goBack()}],
        );
      } else {
        Alert.alert('Error', result.error || 'Failed to send SOS');
      }
    } catch (e: any) {
      Alert.alert('Error', e.message || 'Failed to send SOS');
    } finally {
      setIsSending(false);
    }
  }, [getCurrentPosition, navigation]);

  const handleQuickCall = () => {
    Alert.alert(
      'Emergency Call',
      'This will open your phone dialer with emergency number.',
      [
        {text: 'Cancel', style: 'cancel'},
        {text: 'Call', onPress: () => {}},
      ],
    );
  };

  const progressWidth = holdProgress.interpolate({
    inputRange: [0, 1],
    outputRange: ['0%', '100%'],
  });

  return (
    <View style={styles.container}>
      {/* Header Info */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Emergency SOS</Text>
        <Text style={styles.headerSubtitle}>
          Hold the button for 3 seconds to send your location to all emergency
          contacts
        </Text>
      </View>

      {/* SOS Button */}
      <View style={styles.sosContainer}>
        <TouchableOpacity
          style={[
            styles.sosButton,
            isHolding && styles.sosButtonActive,
            isSending && styles.sosButtonSending,
          ]}
          onPressIn={handlePressIn}
          onPressOut={handlePressOut}
          disabled={isSending}
          activeOpacity={1}>
          {/* Progress Ring */}
          <View style={styles.progressContainer}>
            <Animated.View
              style={[styles.progressBar, {width: progressWidth}]}
            />
          </View>

          <View style={styles.sosButtonInner}>
            <Text style={styles.sosButtonIcon}>
              {isSending ? '⏳' : '🆘'}
            </Text>
            <Text style={styles.sosButtonText}>
              {isSending
                ? 'Sending...'
                : isHolding
                  ? 'Keep Holding...'
                  : 'SOS'}
            </Text>
          </View>
        </TouchableOpacity>

        <Text style={styles.sosHint}>
          {isHolding
            ? 'Keep holding to send SOS'
            : 'Press and hold to activate'}
        </Text>
      </View>

      {/* Quick Actions */}
      <View style={styles.quickActions}>
        <TouchableOpacity
          style={styles.quickAction}
          onPress={handleQuickCall}>
          <Text style={styles.quickActionIcon}>📞</Text>
          <Text style={styles.quickActionText}>Emergency Call</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.quickAction}
          onPress={() => navigation.navigate('EmergencyContacts' as never)}>
          <Text style={styles.quickActionIcon}>👥</Text>
          <Text style={styles.quickActionText}>Manage Contacts</Text>
        </TouchableOpacity>
      </View>

      {/* Info */}
      <View style={styles.infoSection}>
        <Text style={styles.infoTitle}>What happens when you send SOS?</Text>
        <View style={styles.infoItem}>
          <Text style={styles.infoIcon}>📍</Text>
          <Text style={styles.infoText}>
            Your current location is captured with GPS
          </Text>
        </View>
        <View style={styles.infoItem}>
          <Text style={styles.infoIcon}>💬</Text>
          <Text style={styles.infoText}>
            SMS with Google Maps link sent to all emergency contacts
          </Text>
        </View>
        <View style={styles.infoItem}>
          <Text style={styles.infoIcon}>⏱️</Text>
          <Text style={styles.infoText}>
            1-minute cooldown between SOS alerts
          </Text>
        </View>
      </View>

      {/* Cancel Button */}
      <TouchableOpacity
        style={styles.cancelButton}
        onPress={() => navigation.goBack()}>
        <Text style={styles.cancelButtonText}>Cancel</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#1C1C1E',
    padding: 24,
  },
  header: {
    alignItems: 'center',
    marginBottom: 40,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#FFFFFF',
    marginBottom: 12,
  },
  headerSubtitle: {
    fontSize: 16,
    color: '#AEAEB2',
    textAlign: 'center',
    lineHeight: 24,
  },
  sosContainer: {
    alignItems: 'center',
    marginBottom: 40,
  },
  sosButton: {
    width: 200,
    height: 200,
    borderRadius: 100,
    backgroundColor: '#FF3B30',
    justifyContent: 'center',
    alignItems: 'center',
    overflow: 'hidden',
    shadowColor: '#FF3B30',
    shadowOffset: {width: 0, height: 8},
    shadowOpacity: 0.4,
    shadowRadius: 16,
    elevation: 8,
  },
  sosButtonActive: {
    backgroundColor: '#D63030',
    transform: [{scale: 0.95}],
  },
  sosButtonSending: {
    backgroundColor: '#666666',
  },
  progressContainer: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: 8,
    backgroundColor: 'rgba(0, 0, 0, 0.3)',
  },
  progressBar: {
    height: '100%',
    backgroundColor: '#FFFFFF',
  },
  sosButtonInner: {
    alignItems: 'center',
  },
  sosButtonIcon: {
    fontSize: 48,
    marginBottom: 8,
  },
  sosButtonText: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#FFFFFF',
  },
  sosHint: {
    marginTop: 16,
    fontSize: 14,
    color: '#8E8E93',
  },
  quickActions: {
    flexDirection: 'row',
    gap: 16,
    marginBottom: 32,
  },
  quickAction: {
    flex: 1,
    backgroundColor: '#2C2C2E',
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
  },
  quickActionIcon: {
    fontSize: 24,
    marginBottom: 8,
  },
  quickActionText: {
    fontSize: 14,
    color: '#FFFFFF',
    fontWeight: '500',
  },
  infoSection: {
    backgroundColor: '#2C2C2E',
    borderRadius: 12,
    padding: 16,
    marginBottom: 24,
  },
  infoTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#FFFFFF',
    marginBottom: 16,
  },
  infoItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
  },
  infoIcon: {
    fontSize: 16,
    marginRight: 12,
    width: 24,
  },
  infoText: {
    flex: 1,
    fontSize: 14,
    color: '#AEAEB2',
    lineHeight: 20,
  },
  cancelButton: {
    alignItems: 'center',
    paddingVertical: 16,
  },
  cancelButtonText: {
    fontSize: 16,
    color: '#007AFF',
    fontWeight: '600',
  },
});
