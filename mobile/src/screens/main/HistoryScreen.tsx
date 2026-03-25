import React, {useState} from 'react';
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  RefreshControl,
} from 'react-native';

interface LocationHistoryItem {
  id: string;
  latitude: number;
  longitude: number;
  accuracy: number;
  timestamp: Date;
  sharedViaSms: boolean;
  smsRecipients?: string[];
}

// Mock data
const mockHistory: LocationHistoryItem[] = [
  {
    id: '1',
    latitude: 28.6139,
    longitude: 77.209,
    accuracy: 15,
    timestamp: new Date(Date.now() - 5 * 60 * 1000),
    sharedViaSms: false,
  },
  {
    id: '2',
    latitude: 28.6145,
    longitude: 77.2095,
    accuracy: 10,
    timestamp: new Date(Date.now() - 30 * 60 * 1000),
    sharedViaSms: true,
    smsRecipients: ['John Doe'],
  },
  {
    id: '3',
    latitude: 28.615,
    longitude: 77.21,
    accuracy: 20,
    timestamp: new Date(Date.now() - 2 * 60 * 60 * 1000),
    sharedViaSms: false,
  },
  {
    id: '4',
    latitude: 28.612,
    longitude: 77.208,
    accuracy: 12,
    timestamp: new Date(Date.now() - 24 * 60 * 60 * 1000),
    sharedViaSms: true,
    smsRecipients: ['Jane Smith', 'Bob Wilson'],
  },
];

export default function HistoryScreen() {
  const [history, setHistory] = useState<LocationHistoryItem[]>(mockHistory);
  const [refreshing, setRefreshing] = useState(false);
  const [selectedFilter, setSelectedFilter] = useState<'all' | 'sms'>('all');

  const filteredHistory =
    selectedFilter === 'sms'
      ? history.filter(item => item.sharedViaSms)
      : history;

  const onRefresh = async () => {
    setRefreshing(true);
    // TODO: Fetch history from API
    await new Promise(resolve => setTimeout(resolve, 1000));
    setRefreshing(false);
  };

  const formatTimeAgo = (date: Date) => {
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / (1000 * 60));
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;
    return date.toLocaleDateString();
  };

  const renderHistoryItem = ({item}: {item: LocationHistoryItem}) => (
    <TouchableOpacity style={styles.historyCard}>
      <View style={styles.historyIcon}>
        <Text style={styles.historyIconText}>
          {item.sharedViaSms ? '💬' : '📍'}
        </Text>
      </View>
      <View style={styles.historyInfo}>
        <View style={styles.historyHeader}>
          <Text style={styles.historyTime}>{formatTimeAgo(item.timestamp)}</Text>
          {item.sharedViaSms && (
            <View style={styles.smsBadge}>
              <Text style={styles.smsBadgeText}>SMS</Text>
            </View>
          )}
        </View>
        <Text style={styles.historyCoords}>
          {item.latitude.toFixed(6)}, {item.longitude.toFixed(6)}
        </Text>
        <Text style={styles.historyAccuracy}>
          Accuracy: ±{item.accuracy}m
        </Text>
        {item.smsRecipients && item.smsRecipients.length > 0 && (
          <Text style={styles.historyRecipients}>
            Sent to: {item.smsRecipients.join(', ')}
          </Text>
        )}
      </View>
      <TouchableOpacity style={styles.historyAction}>
        <Text style={styles.historyActionText}>🗺️</Text>
      </TouchableOpacity>
    </TouchableOpacity>
  );

  const renderHeader = () => (
    <View style={styles.headerContainer}>
      {/* Filter Tabs */}
      <View style={styles.filterTabs}>
        <TouchableOpacity
          style={[
            styles.filterTab,
            selectedFilter === 'all' && styles.filterTabActive,
          ]}
          onPress={() => setSelectedFilter('all')}>
          <Text
            style={[
              styles.filterTabText,
              selectedFilter === 'all' && styles.filterTabTextActive,
            ]}>
            All Locations
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[
            styles.filterTab,
            selectedFilter === 'sms' && styles.filterTabActive,
          ]}
          onPress={() => setSelectedFilter('sms')}>
          <Text
            style={[
              styles.filterTabText,
              selectedFilter === 'sms' && styles.filterTabTextActive,
            ]}>
            Shared via SMS
          </Text>
        </TouchableOpacity>
      </View>

      {/* Stats */}
      <View style={styles.statsContainer}>
        <View style={styles.statItem}>
          <Text style={styles.statValue}>{history.length}</Text>
          <Text style={styles.statLabel}>Total Locations</Text>
        </View>
        <View style={styles.statDivider} />
        <View style={styles.statItem}>
          <Text style={styles.statValue}>
            {history.filter(h => h.sharedViaSms).length}
          </Text>
          <Text style={styles.statLabel}>SMS Shared</Text>
        </View>
        <View style={styles.statDivider} />
        <View style={styles.statItem}>
          <Text style={styles.statValue}>30</Text>
          <Text style={styles.statLabel}>Days Kept</Text>
        </View>
      </View>
    </View>
  );

  return (
    <View style={styles.container}>
      <FlatList
        data={filteredHistory}
        renderItem={renderHistoryItem}
        keyExtractor={item => item.id}
        ListHeaderComponent={renderHeader}
        contentContainerStyle={styles.listContent}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
        }
        ListEmptyComponent={
          <View style={styles.emptyContainer}>
            <Text style={styles.emptyIcon}>📍</Text>
            <Text style={styles.emptyTitle}>No Location History</Text>
            <Text style={styles.emptySubtitle}>
              {selectedFilter === 'sms'
                ? 'No locations shared via SMS yet'
                : 'Start sharing your location to see history'}
            </Text>
          </View>
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F2F2F7',
  },
  headerContainer: {
    backgroundColor: '#FFFFFF',
    paddingBottom: 16,
    marginBottom: 8,
  },
  filterTabs: {
    flexDirection: 'row',
    padding: 16,
    paddingBottom: 0,
    gap: 8,
  },
  filterTab: {
    flex: 1,
    paddingVertical: 10,
    alignItems: 'center',
    borderRadius: 8,
    backgroundColor: '#F2F2F7',
  },
  filterTabActive: {
    backgroundColor: '#007AFF',
  },
  filterTabText: {
    fontSize: 14,
    fontWeight: '500',
    color: '#8E8E93',
  },
  filterTabTextActive: {
    color: '#FFFFFF',
  },
  statsContainer: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    paddingTop: 16,
  },
  statItem: {
    flex: 1,
    alignItems: 'center',
  },
  statValue: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#000000',
  },
  statLabel: {
    fontSize: 12,
    color: '#8E8E93',
    marginTop: 4,
  },
  statDivider: {
    width: 1,
    backgroundColor: '#E5E5EA',
    marginVertical: 4,
  },
  listContent: {
    paddingHorizontal: 16,
    paddingBottom: 24,
  },
  historyCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#FFFFFF',
    padding: 16,
    borderRadius: 12,
    marginBottom: 8,
  },
  historyIcon: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#F2F2F7',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  historyIconText: {
    fontSize: 20,
  },
  historyInfo: {
    flex: 1,
  },
  historyHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 4,
  },
  historyTime: {
    fontSize: 14,
    fontWeight: '600',
    color: '#000000',
  },
  smsBadge: {
    backgroundColor: '#E5F2FF',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 4,
    marginLeft: 8,
  },
  smsBadgeText: {
    fontSize: 11,
    fontWeight: '600',
    color: '#007AFF',
  },
  historyCoords: {
    fontSize: 13,
    color: '#666666',
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
    marginBottom: 2,
  },
  historyAccuracy: {
    fontSize: 12,
    color: '#8E8E93',
  },
  historyRecipients: {
    fontSize: 12,
    color: '#007AFF',
    marginTop: 4,
  },
  historyAction: {
    padding: 8,
  },
  historyActionText: {
    fontSize: 20,
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
    paddingHorizontal: 40,
  },
});
