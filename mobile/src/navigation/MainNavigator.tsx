import React from 'react';
import {createBottomTabNavigator} from '@react-navigation/bottom-tabs';
import {createNativeStackNavigator} from '@react-navigation/native-stack';
import {View, Text, StyleSheet} from 'react-native';

import MapScreen from '../screens/main/MapScreen';
import FriendsScreen from '../screens/main/FriendsScreen';
import HistoryScreen from '../screens/main/HistoryScreen';
import SettingsScreen from '../screens/main/SettingsScreen';
import SosScreen from '../screens/emergency/SosScreen';
import EmergencyContactsScreen from '../screens/emergency/EmergencyContactsScreen';

export type MainTabParamList = {
  Map: undefined;
  Friends: undefined;
  History: undefined;
  Settings: undefined;
};

export type MainStackParamList = {
  MainTabs: undefined;
  Sos: undefined;
  EmergencyContacts: undefined;
};

const Tab = createBottomTabNavigator<MainTabParamList>();
const Stack = createNativeStackNavigator<MainStackParamList>();

// Simple icon component (replace with proper icons later)
function TabIcon({name, focused}: {name: string; focused: boolean}) {
  const icons: Record<string, string> = {
    Map: '🗺️',
    Friends: '👥',
    History: '📍',
    Settings: '⚙️',
  };
  return (
    <View style={styles.iconContainer}>
      <Text style={[styles.icon, focused && styles.iconFocused]}>
        {icons[name] || '•'}
      </Text>
    </View>
  );
}

function MainTabs() {
  return (
    <Tab.Navigator
      screenOptions={({route}) => ({
        tabBarIcon: ({focused}) => <TabIcon name={route.name} focused={focused} />,
        tabBarActiveTintColor: '#007AFF',
        tabBarInactiveTintColor: '#8E8E93',
        headerShown: true,
        headerStyle: {
          backgroundColor: '#FFFFFF',
        },
      })}>
      <Tab.Screen
        name="Map"
        component={MapScreen}
        options={{title: 'Location'}}
      />
      <Tab.Screen
        name="Friends"
        component={FriendsScreen}
        options={{title: 'Friends'}}
      />
      <Tab.Screen
        name="History"
        component={HistoryScreen}
        options={{title: 'History'}}
      />
      <Tab.Screen
        name="Settings"
        component={SettingsScreen}
        options={{title: 'Settings'}}
      />
    </Tab.Navigator>
  );
}

export default function MainNavigator() {
  return (
    <Stack.Navigator>
      <Stack.Screen
        name="MainTabs"
        component={MainTabs}
        options={{headerShown: false}}
      />
      <Stack.Screen
        name="Sos"
        component={SosScreen}
        options={{
          title: 'Emergency SOS',
          presentation: 'fullScreenModal',
          headerStyle: {backgroundColor: '#FF3B30'},
          headerTintColor: '#FFFFFF',
        }}
      />
      <Stack.Screen
        name="EmergencyContacts"
        component={EmergencyContactsScreen}
        options={{title: 'Emergency Contacts'}}
      />
    </Stack.Navigator>
  );
}

const styles = StyleSheet.create({
  iconContainer: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    fontSize: 24,
    opacity: 0.6,
  },
  iconFocused: {
    opacity: 1,
  },
});
