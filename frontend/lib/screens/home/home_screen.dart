import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../theme/app_colors.dart';
import '../chat/chat_list_screen.dart';
import '../invites/invites_screen.dart';
import '../search/search_screen.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _profileTabIndex = 3;

  int _currentIndex = 0;
  final _invitesKey = GlobalKey<InvitesScreenState>();
  final _profileKey = GlobalKey<ProfileScreenState>();

  late final List<Widget> _screens = [
    const ChatListScreen(),
    InvitesScreen(key: _invitesKey),
    SearchScreen(onInviteSent: _refreshInvites),
    ProfileScreen(key: _profileKey),
  ];

  Future<void> _refreshInvites() async {
    await _invitesKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) async {
          if (index == _currentIndex) return;

          if (_currentIndex == _profileTabIndex) {
            final canLeave =
                await _profileKey.currentState?.confirmDiscardChangesIfNeeded() ?? true;
            if (!canLeave) return;
          }

          setState(() {
            _currentIndex = index;
          });
          if (index == 0) {
            await context.read<ChatProvider>().fetchChats();
          }
          if (index == 1) {
            await _refreshInvites();
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        backgroundColor: Colors.white,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_rounded),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mark_email_unread_rounded),
            label: 'Invites',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_rounded),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
