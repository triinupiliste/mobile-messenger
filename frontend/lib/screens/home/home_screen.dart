import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/invite_provider.dart';
import '../../theme/app_colors.dart';
import '../chat/chat_list_screen.dart';
import '../invites/invites_screen.dart';
import '../search/search_screen.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  // Lets screens pushed on top of HomeScreen (e.g. ChatRoomScreen) switch
  // back to a specific tab once popped — e.g. after removing a friend, we
  // want the user to land back on the Chats tab specifically, regardless of
  // which tab was active when they navigated into the chat.
  static final GlobalKey<HomeScreenState> homeKey = GlobalKey<HomeScreenState>();

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  static const _chatsTabIndex = 0;
  static const _invitesTabIndex = 1;
  static const _profileTabIndex = 3;

  int _currentIndex = 0;
  final _profileKey = GlobalKey<ProfileScreenState>();

  // Switches to the Chats tab and refreshes it, mirroring what tapping the
  // Chats tab itself does. Used by ChatRoomScreen after removing a friend.
  void switchToChatsTab() {
    if (_currentIndex != _chatsTabIndex) {
      setState(() => _currentIndex = _chatsTabIndex);
    }
    context.read<ChatProvider>().fetchChats();
  }

  late final List<Widget> _screens = [
    const ChatListScreen(),
    const InvitesScreen(),
    SearchScreen(onInviteSent: () => context.read<InviteProvider>().fetchInvites()),
    ProfileScreen(key: _profileKey),
  ];

  @override
  Widget build(BuildContext context) {
    final totalUnreadMessages = context.watch<ChatProvider>().totalUnreadCount;
    final unseenInvites = context.watch<InviteProvider>().unseenCount;

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
          if (index == _invitesTabIndex) {
            await context.read<InviteProvider>().fetchInvites();
            if (mounted) {
              context.read<InviteProvider>().markIncomingSeen();
            }
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        backgroundColor: Colors.white,
        elevation: 8,
        items: [
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: totalUnreadMessages > 0,
              label: Text(totalUnreadMessages > 99 ? '99+' : '$totalUnreadMessages'),
              child: const Icon(Icons.chat_bubble_rounded),
            ),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: unseenInvites > 0,
              label: Text(unseenInvites > 99 ? '99+' : '$unseenInvites'),
              child: const Icon(Icons.mail_outline_rounded),
            ),
            label: 'Invites',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.search_rounded),
            label: 'Search',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

