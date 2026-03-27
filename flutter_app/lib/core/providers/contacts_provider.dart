import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/contact_model.dart';
import '../../shared/constants/app_constants.dart';

final contactsProvider =
    StateNotifierProvider<ContactsNotifier, ContactsState>((ref) {
  return ContactsNotifier();
});

class ContactsState {
  final List<ContactModel> contacts;
  final bool isLoading;
  final String? error;

  const ContactsState({
    this.contacts = const [],
    this.isLoading = false,
    this.error,
  });

  List<ContactModel> get sosContacts =>
      contacts.where((c) => c.isSosContact).toList();

  List<ContactModel> get locationSharingContacts =>
      contacts.where((c) => c.isLocationSharing).toList();

  ContactsState copyWith({
    List<ContactModel>? contacts,
    bool? isLoading,
    String? error,
  }) {
    return ContactsState(
      contacts: contacts ?? this.contacts,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ContactsNotifier extends StateNotifier<ContactsState> {
  final _uuid = const Uuid();

  ContactsNotifier() : super(const ContactsState(isLoading: true)) {
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final box =
          await Hive.openBox<ContactModel>(AppConstants.contactsBoxName);
      final contacts = box.values.toList();
      state = ContactsState(contacts: contacts, isLoading: false);
    } catch (e) {
      state = ContactsState(isLoading: false, error: e.toString());
    }
  }

  Future<void> addContact(ContactModel contact) async {
    try {
      final box =
          await Hive.openBox<ContactModel>(AppConstants.contactsBoxName);
      await box.add(contact);

      state = state.copyWith(contacts: [...state.contacts, contact]);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> addContactByFields({
    required String name,
    required String phone,
    String? email,
    String? relationship,
    bool isSosContact = true,
    bool isLocationSharing = false,
  }) async {
    final contact = ContactModel(
      id: _uuid.v4(),
      name: name,
      phone: phone,
      email: email,
      relationship: relationship,
      isSosContact: isSosContact,
      isLocationSharing: isLocationSharing,
      addedAt: DateTime.now(),
    );
    await addContact(contact);
  }

  Future<void> removeContact(String id) async {
    await deleteContact(id);
  }

  Future<void> updateContact(ContactModel contact) async {
    try {
      final box =
          await Hive.openBox<ContactModel>(AppConstants.contactsBoxName);
      final index = state.contacts.indexWhere((c) => c.id == contact.id);

      if (index != -1) {
        await box.putAt(index, contact);

        final updatedContacts = [...state.contacts];
        updatedContacts[index] = contact;
        state = state.copyWith(contacts: updatedContacts);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteContact(String id) async {
    try {
      final box =
          await Hive.openBox<ContactModel>(AppConstants.contactsBoxName);
      final index = state.contacts.indexWhere((c) => c.id == id);

      if (index != -1) {
        await box.deleteAt(index);

        final updatedContacts =
            state.contacts.where((c) => c.id != id).toList();
        state = state.copyWith(contacts: updatedContacts);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> toggleSosContact(String id) async {
    final contact = state.contacts.firstWhere((c) => c.id == id);
    final updated = contact.copyWith(isSosContact: !contact.isSosContact);
    await updateContact(updated);
  }

  Future<void> toggleLocationSharing(String id) async {
    final contact = state.contacts.firstWhere((c) => c.id == id);
    final updated =
        contact.copyWith(isLocationSharing: !contact.isLocationSharing);
    await updateContact(updated);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}
