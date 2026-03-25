import React, {useState} from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  Switch,
  StyleSheet,
  Alert,
} from 'react-native';
import {useNavigation} from '@react-navigation/native';
import {NativeStackNavigationProp} from '@react-navigation/native-stack';
import {MainStackParamList} from '../../navigation/MainNavigator';
import {useAuth} from '../../modules/auth/AuthContext';

type SettingsNavProp = NativeStackNavigationProp<MainStackParamList, 'MainTabs'>;

interface SettingSection {
  title: string;
  items: SettingItem[];
}

interface SettingItem {
  key: string;
  label: string;
  type: 'toggle' | 'link' | 'value';
  value?: boolean | string;
  onPress?: () => void;
  destructive?: boolean;
}

export default function SettingsScreen() {
  const navigation = useNavigation<SettingsNavProp>();
  const {user, signOut} = useAuth();

  // SMS Settings State
  const [autoFallbackEnabled, setAutoFallbackEnabled] = useState(true);
  const [scheduledSmsEnabled, setScheduledSmsEnabled] = useState(false);
  const [includeGoogleMapsLink, setIncludeGoogleMapsLink] = useState(true);
  const [includeRawCoordinates, setIncludeRawCoordinates] = useState(true);
  const [includeAccuracyInfo, setIncludeAccuracyInfo] = useState(true);

  // Location Settings State
  const [backgroundTracking, setBackgroundTracking] = useState(true);
  const [highAccuracyMode, setHighAccuracyMode] = useState(false);

  const handleSignOut = () => {
    Alert.alert(
      'Sign Out',
      'Are you sure you want to sign out?',
      [
        {text: 'Cancel', style: 'cancel'},
        {
          text: 'Sign Out',
          style: 'destructive',
          onPress: async () => {
            try {
              await signOut();
            } catch (e: any) {
              Alert.alert('Error', e.message || 'Failed to sign out');
            }
          },
        },
      ],
    );
  };

  const handleDeleteAccount = () => {
    Alert.alert(
      'Delete Account',
      'This will permanently delete your account and all associated data. This action cannot be undone.',
      [
        {text: 'Cancel', style: 'cancel'},
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            // TODO: Implement account deletion
            Alert.alert('Not Implemented', 'Account deletion is not yet implemented');
          },
        },
      ],
    );
  };

  const sections: SettingSection[] = [
    {
      title: 'Account',
      items: [
        {
          key: 'profile',
          label: 'Edit Profile',
          type: 'link',
          value: user?.name || user?.email || user?.phone || 'Not set',
          onPress: () => {},
        },
        {
          key: 'phone',
          label: 'Phone Number',
          type: 'value',
          value: user?.phone || 'Not set',
        },
      ],
    },
    {
      title: 'SMS Settings',
      items: [
        {
          key: 'autoFallback',
          label: 'Auto SMS when offline',
          type: 'toggle',
          value: autoFallbackEnabled,
          onPress: () => setAutoFallbackEnabled(!autoFallbackEnabled),
        },
        {
          key: 'scheduledSms',
          label: 'Scheduled SMS updates',
          type: 'toggle',
          value: scheduledSmsEnabled,
          onPress: () => setScheduledSmsEnabled(!scheduledSmsEnabled),
        },
        {
          key: 'googleMapsLink',
          label: 'Include Google Maps link',
          type: 'toggle',
          value: includeGoogleMapsLink,
          onPress: () => setIncludeGoogleMapsLink(!includeGoogleMapsLink),
        },
        {
          key: 'rawCoordinates',
          label: 'Include raw coordinates',
          type: 'toggle',
          value: includeRawCoordinates,
          onPress: () => setIncludeRawCoordinates(!includeRawCoordinates),
        },
        {
          key: 'accuracyInfo',
          label: 'Include accuracy info',
          type: 'toggle',
          value: includeAccuracyInfo,
          onPress: () => setIncludeAccuracyInfo(!includeAccuracyInfo),
        },
      ],
    },
    {
      title: 'Emergency',
      items: [
        {
          key: 'emergencyContacts',
          label: 'Emergency Contacts',
          type: 'link',
          onPress: () => navigation.navigate('EmergencyContacts'),
        },
        {
          key: 'testSos',
          label: 'Test SOS Alert',
          type: 'link',
          onPress: () => {
            Alert.alert(
              'Test SOS',
              'This will send a test SOS alert to your emergency contacts. Continue?',
              [
                {text: 'Cancel', style: 'cancel'},
                {text: 'Send Test', onPress: () => {}},
              ],
            );
          },
        },
      ],
    },
    {
      title: 'Location',
      items: [
        {
          key: 'backgroundTracking',
          label: 'Background tracking',
          type: 'toggle',
          value: backgroundTracking,
          onPress: () => setBackgroundTracking(!backgroundTracking),
        },
        {
          key: 'highAccuracy',
          label: 'High accuracy mode',
          type: 'toggle',
          value: highAccuracyMode,
          onPress: () => setHighAccuracyMode(!highAccuracyMode),
        },
        {
          key: 'historyRetention',
          label: 'History retention',
          type: 'value',
          value: '30 days',
        },
      ],
    },
    {
      title: 'Privacy',
      items: [
        {
          key: 'clearHistory',
          label: 'Clear location history',
          type: 'link',
          destructive: true,
          onPress: () => {
            Alert.alert(
              'Clear History',
              'This will delete all your location history. Continue?',
              [
                {text: 'Cancel', style: 'cancel'},
                {text: 'Clear', style: 'destructive', onPress: () => {}},
              ],
            );
          },
        },
        {
          key: 'exportData',
          label: 'Export my data',
          type: 'link',
          onPress: () => {},
        },
      ],
    },
    {
      title: 'About',
      items: [
        {
          key: 'version',
          label: 'App Version',
          type: 'value',
          value: '1.0.0',
        },
        {
          key: 'terms',
          label: 'Terms of Service',
          type: 'link',
          onPress: () => {},
        },
        {
          key: 'privacy',
          label: 'Privacy Policy',
          type: 'link',
          onPress: () => {},
        },
      ],
    },
    {
      title: '',
      items: [
        {
          key: 'signOut',
          label: 'Sign Out',
          type: 'link',
          destructive: true,
          onPress: handleSignOut,
        },
        {
          key: 'deleteAccount',
          label: 'Delete Account',
          type: 'link',
          destructive: true,
          onPress: handleDeleteAccount,
        },
      ],
    },
  ];

  const renderSettingItem = (item: SettingItem) => {
    switch (item.type) {
      case 'toggle':
        return (
          <View style={styles.settingRow} key={item.key}>
            <Text style={styles.settingLabel}>{item.label}</Text>
            <Switch
              value={item.value as boolean}
              onValueChange={() => item.onPress?.()}
              trackColor={{false: '#E5E5EA', true: '#34C759'}}
              thumbColor="#FFFFFF"
            />
          </View>
        );
      case 'link':
        return (
          <TouchableOpacity
            style={styles.settingRow}
            key={item.key}
            onPress={item.onPress}>
            <Text
              style={[
                styles.settingLabel,
                item.destructive && styles.settingLabelDestructive,
              ]}>
              {item.label}
            </Text>
            {item.value && (
              <Text style={styles.settingValue}>{item.value}</Text>
            )}
            <Text style={styles.settingArrow}>›</Text>
          </TouchableOpacity>
        );
      case 'value':
        return (
          <View style={styles.settingRow} key={item.key}>
            <Text style={styles.settingLabel}>{item.label}</Text>
            <Text style={styles.settingValue}>{item.value}</Text>
          </View>
        );
    }
  };

  return (
    <ScrollView style={styles.container}>
      {sections.map((section, index) => (
        <View key={index} style={styles.section}>
          {section.title && (
            <Text style={styles.sectionTitle}>{section.title}</Text>
          )}
          <View style={styles.sectionContent}>
            {section.items.map(renderSettingItem)}
          </View>
        </View>
      ))}
      <View style={styles.footer} />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F2F2F7',
  },
  section: {
    marginTop: 24,
  },
  sectionTitle: {
    fontSize: 13,
    fontWeight: '600',
    color: '#8E8E93',
    paddingHorizontal: 16,
    paddingBottom: 8,
    textTransform: 'uppercase',
  },
  sectionContent: {
    backgroundColor: '#FFFFFF',
    borderTopWidth: 1,
    borderBottomWidth: 1,
    borderColor: '#E5E5EA',
  },
  settingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 14,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#E5E5EA',
  },
  settingLabel: {
    flex: 1,
    fontSize: 16,
    color: '#000000',
  },
  settingLabelDestructive: {
    color: '#FF3B30',
  },
  settingValue: {
    fontSize: 16,
    color: '#8E8E93',
    marginRight: 8,
  },
  settingArrow: {
    fontSize: 20,
    color: '#C7C7CC',
  },
  footer: {
    height: 40,
  },
});
