import React from 'react';
import {StatusBar} from 'react-native';
import {NavigationContainer} from '@react-navigation/native';
import {SafeAreaProvider} from 'react-native-safe-area-context';
import {GestureHandlerRootView} from 'react-native-gesture-handler';

import {AuthProvider} from './src/modules/auth/AuthContext';
import {NetworkProvider} from './src/modules/network/NetworkContext';
import {LocationProvider} from './src/modules/location/LocationContext';
import RootNavigator from './src/navigation/RootNavigator';

function App(): React.JSX.Element {
  return (
    <GestureHandlerRootView style={{flex: 1}}>
      <SafeAreaProvider>
        <NavigationContainer>
          <AuthProvider>
            <NetworkProvider>
              <LocationProvider>
                <StatusBar barStyle="dark-content" />
                <RootNavigator />
              </LocationProvider>
            </NetworkProvider>
          </AuthProvider>
        </NavigationContainer>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

export default App;
