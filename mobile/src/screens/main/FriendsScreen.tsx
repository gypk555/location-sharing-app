import React, {useState} from 'react';
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  TextInput,
  RefreshControl,
} from 'react-native';

// Mock data for friends
interface Friend {
  id: string;
  name: string;
  phone: string;
  status: 'online' | 'offline' | 'sharing';
  lastLocation?: {
    latitude: number;
    longitude: number;
    timestamp: Date;
  };
  canViewLocation: boolean;
  canReceiveSms: boolean;
}

const mockFriends: Friend[] = [
  {
    id: '1',
    name: 'John Doe',
    phone: '+91 98765 43210',
    status: 'sharing',
    lastLocation: {
      latitude: 28.6139,
      longitude: 77.209,
      timestamp: new Date(),
    },
    canViewLocation: true,
    canReceiveSms: true,
  },
  {
    id: '2',
    name: 'Jane Smith',
    phone: '+91 98765 43211',
    status: 'online',
    canViewLocation: true,
    canReceiveSms: false,
  },
  {
    id: '3',
    name: 'Bob Wilson',
    phone: '+91 98765 43212',
    status: 'offline',
    canViewLocation: false,
    canReceiveSms: true,
  },
];

export default function FriendsScreen() {
  const [friends, setFriends] = useState<Friend[]>(mockFriends);
  const [searchQuery, setSearchQuery] = useState('');
  const [refreshing, setRefreshing] = useState(false);

  const filteredFriends = friends.filter(friend =>
    friend.name.toLowerCase().includes(searchQuery.toLowerCase()),
  );

  const onRefresh = async () => {
    setRefreshing(true);
    // TODO: Fetch friends from API
    await new Promise(resolve => setTimeout(resolve, 1000));
    setRefreshing(false);
  };

  const getStatusColor = (status: Friend['status']) => {
    switch (status) {
      case 'sharing':
        return '#007AFF';
      case 'online':
        return '#34C759';
      case 'offline':
        return '#8E8E93';
    }
  };

  const getStatusText = (status: Friend['status']) => {
    switch (status) {
      case 'sharing':
        return 'Sharing location';
      case 'online':
        return 'Online';
      case 'offline':
        return 'Offline';
    }
  };

  const renderFriend = ({item}: {item: Friend}) => (
    <TouchableOpacity style={styles.friendCard}>
      <View style={styles.friendAvatar}>
        <Text style={styles.friendAvatarText}>
          {item.name.charAt(0).toUpperCase()}
        </Text>
        <View
          style={[
            styles.statusIndicator,
            {backgroundColor: getStatusColor(item.status)},
          ]}
        />
      </View>
      <View style={styles.friendInfo}>
        <Text style={styles.friendName}>{item.name}</Text>
        <Text style={styles.friendStatus}>{getStatusText(item.status)}</Text>
        {item.lastLocation && item.status === 'sharing' && (
          <Text style={styles.friendLocation}>
            Last update: {item.lastLocation.timestamp.toLocaleTimeString()}
          </Text>
        )}
      </View>
      <View style={styles.friendActions}>
        <View style={styles.permissionBadges}>
          {item.canViewLocation && (
            <View style={[styles.badge, styles.badgeLocation]}>
              <Text style={styles.badgeText}>📍</Text>
            </View>
          )}
          {item.canReceiveSms && (
            <View style={[styles.badge, styles.badgeSms]}>
              <Text style={styles.badgeText}>💬</Text>
            </View>
          )}
        </View>
      </View>
    </TouchableOpacity>
  );

  return (
    <View style={styles.container}>
      {/* Search Bar */}
      <View style={styles.searchContainer}>
        <TextInput
          style={styles.searchInput}
          placeholder="Search friends..."
          value={searchQuery}
          onChangeText={setSearchQuery}
          placeholderTextColor="#8E8E93"
        />
      </View>

      {/* Add Friend Button */}
      <TouchableOpacity style={styles.addButton}>
        <Text style={styles.addButtonIcon}>+</Text>
        <Text style={styles.addButtonText}>Add Friend</Text>
      </TouchableOpacity>

      {/* Friends List */}
      <FlatList
        data={filteredFriends}
        renderItem={renderFriend}
        keyExtractor={item => item.id}
        contentContainerStyle={styles.listContent}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
        }
        ListEmptyComponent={
          <View style={styles.emptyContainer}>
            <Text style={styles.emptyIcon}>👥</Text>
            <Text style={styles.emptyTitle}>No Friends Yet</Text>
            <Text style={styles.emptySubtitle}>
              Add friends to share your location with them
            </Text>
          </View>
        }
      />

      {/* Pending Requests Section (placeholder) */}
      {friends.length > 0 && (
        <View style={styles.pendingSection}>
          <TouchableOpacity style={styles.pendingButton}>
            <Text style={styles.pendingButtonText}>
              Friend Requests (0)
            </Text>
            <Text style={styles.pendingButtonArrow}>›</Text>
          </TouchableOpacity>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F2F2F7',
  },
  searchContainer: {
    padding: 16,
    backgroundColor: '#FFFFFF',
  },
  searchInput: {
    backgroundColor: '#F2F2F7',
    borderRadius: 10,
    paddingHorizontal: 16,
    paddingVertical: 12,
    fontSize: 16,
  },
  addButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#007AFF',
    marginHorizontal: 16,
    marginVertical: 12,
    paddingVertical: 14,
    borderRadius: 12,
  },
  addButtonIcon: {
    fontSize: 20,
    color: '#FFFFFF',
    fontWeight: 'bold',
    marginRight: 8,
  },
  addButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#FFFFFF',
  },
  listContent: {
    paddingHorizontal: 16,
    paddingBottom: 100,
  },
  friendCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#FFFFFF',
    padding: 16,
    borderRadius: 12,
    marginBottom: 8,
  },
  friendAvatar: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: '#E5E5EA',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  friendAvatarText: {
    fontSize: 20,
    fontWeight: '600',
    color: '#8E8E93',
  },
  statusIndicator: {
    position: 'absolute',
    bottom: 0,
    right: 0,
    width: 14,
    height: 14,
    borderRadius: 7,
    borderWidth: 2,
    borderColor: '#FFFFFF',
  },
  friendInfo: {
    flex: 1,
  },
  friendName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#000000',
    marginBottom: 2,
  },
  friendStatus: {
    fontSize: 13,
    color: '#8E8E93',
  },
  friendLocation: {
    fontSize: 12,
    color: '#AEAEB2',
    marginTop: 2,
  },
  friendActions: {
    alignItems: 'flex-end',
  },
  permissionBadges: {
    flexDirection: 'row',
    gap: 4,
  },
  badge: {
    width: 28,
    height: 28,
    borderRadius: 14,
    justifyContent: 'center',
    alignItems: 'center',
  },
  badgeLocation: {
    backgroundColor: '#E5F2FF',
  },
  badgeSms: {
    backgroundColor: '#E5FFE5',
  },
  badgeText: {
    fontSize: 14,
  },
  emptyContainer: {
    alignItems: 'center',
    paddingVertical: 60,
  },
  emptyIcon: {
    fontSize: 64,
    marginBottom: 16,
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: '600',
    color: '#000000',
    marginBottom: 8,
  },
  emptySubtitle: {
    fontSize: 14,
    color: '#8E8E93',
    textAlign: 'center',
  },
  pendingSection: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: '#FFFFFF',
    borderTopWidth: 1,
    borderTopColor: '#E5E5EA',
    paddingVertical: 8,
    paddingHorizontal: 16,
  },
  pendingButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 12,
  },
  pendingButtonText: {
    fontSize: 14,
    color: '#007AFF',
    fontWeight: '500',
  },
  pendingButtonArrow: {
    fontSize: 20,
    color: '#007AFF',
  },
});
