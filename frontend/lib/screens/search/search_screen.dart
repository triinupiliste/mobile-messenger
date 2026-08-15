import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/user_avatar.dart';
import '../chat/chat_room_screen.dart';

class SearchScreen extends StatefulWidget {
  final Future<void> Function()? onInviteSent;

  const SearchScreen({super.key, this.onInviteSent});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _sendingInviteTo = {};

  Timer? _searchDebounce;
  List<UserModel> _searchResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _searchError;
  int _searchVersion = 0;

  void _scheduleSearch(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    final version = ++_searchVersion;

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
        _hasSearched = false;
        _searchError = null;
      });
      return;
    }

    // Only set loading if we don't already have results, preventing screen flashing/blanking
    if (_searchResults.isEmpty) {
      setState(() {
        _isLoading = true;
        _hasSearched = true;
        _searchError = null;
      });
    }

    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _searchUsers(query, version),
    );
  }

  Future<void> _searchUsers(String query, int version) async {
    try {
      final response = await ApiService.searchUsers(query);

      // Discard this response if a newer search has started in the meantime.
      if (!mounted || version != _searchVersion) {
        return;
      }

      final users = <UserModel>[];
      for (final item in response) {
        if (item is Map) {
          final user = UserModel.fromJson(Map<String, dynamic>.from(item));
          if (user.id.isNotEmpty) users.add(user);
        }
      }

      setState(() {
        _searchResults = users;
        _isLoading = false;
        _searchError = null;
        _hasSearched = true;
      });
    } catch (error) {
      if (!mounted || version != _searchVersion) return;
      setState(() {
        // Keep previous results if an error occurs instead of wiping to blank
        _isLoading = false;
        _searchError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _sendInvite(UserModel user) async {
    if (_sendingInviteTo.contains(user.id)) return;
    setState(() => _sendingInviteTo.add(user.id));

    try {
      await ApiService.sendInvite(user.id);
      if (!mounted) return;

      _searchDebounce?.cancel();
      _searchVersion++;
      _searchController.clear();
      FocusScope.of(context).unfocus();
      setState(() {
        _searchResults = [];
        _isLoading = false;
        _hasSearched = false;
        _searchError = null;
      });

      await widget.onInviteSent?.call();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('Invitation sent'),
          content: Text(
            'Your invitation to ${user.username} was sent and is pending.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingInviteTo.remove(user.id));
      }
    }
  }

  Widget _buildUserCard(UserModel user) {
    final isSending = _sendingInviteTo.contains(user.id);
    final trimmedUsername = user.username.trim();
    final displayName = trimmedUsername.isEmpty ? 'Unknown user' : trimmedUsername;

    Widget actionWidget;
    if (user.relationshipStatus == 'friends') {
      actionWidget = ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(84, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: user.chatId == null
            ? null
            : () {
                FocusScope.of(context).unfocus();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatRoomScreen(
                      chatId: user.chatId!,
                      contactId: user.id,
                      contactName: displayName,
                    ),
                  ),
                );
              },
        child: const Text('Send Message'),
      );
    } else if (user.relationshipStatus == 'pending') {
      actionWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Pending',
          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
        ),
      );
    } else {
      actionWidget = ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(84, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: isSending ? null : () => _sendInvite(user),
        child: isSending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Invite'),
      );
    }

    return Container(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            UserAvatar(
              avatarUrl: user.avatarUrl,
              displayName: displayName,
              radius: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            actionWidget,
          ],
        ),
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD4D4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_searchError != null) {
      return Center(
        child: Text(
          _searchError!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.error),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          _hasSearched
              ? 'No users found for "${_searchController.text.trim()}"'
              : 'Enter a username or email to search',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildUserCard(_searchResults[index]),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: _scheduleSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by username or email...',
                prefixIcon: Icon(Icons.search, color: AppColors.primary),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _scheduleSearch('');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildSearchBody()),
          ],
        ),
      ),
    );
  }
}
