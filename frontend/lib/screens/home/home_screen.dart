import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/invite_provider.dart';
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

  // Note: this is a getter (not a `late final` field computed once) so it
  // constructs fresh widget instances on every build. IndexedStack's
  // Element.updateChild skips rebuilding a child entirely if the exact same
  // widget instance is passed again — with a fixed field (and `const`
  // constructors, which Dart canonicalizes to one shared instance regardless
  // of how many times they're constructed), that meant these tabs (Profile's
  // avatar/logout button, Search's icon, etc.) never picked up theme changes
  // made via RestartWidget while sitting in the background, only updating
  // once something inside them called setState directly. `const` is
  // deliberately dropped below for the same reason. None of these widgets
  // have (or need) Keys, so recreating them each build still preserves each
  // tab's State via the standard same-type/same-slot element matching.
  List<Widget> get _screens => [
    ChatListScreen(),
    InvitesScreen(),
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
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) async {
              if (index == _currentIndex) return;

              // Capture providers *before* any async gaps to avoid context warnings
              final chatProvider = context.read<ChatProvider>();
              final inviteProvider = context.read<InviteProvider>();

              if (_currentIndex == _profileTabIndex) {
                final canLeave =
                    await _profileKey.currentState?.confirmDiscardChangesIfNeeded() ?? true;
                if (!canLeave) return;
              }

              if (!mounted) return;

              setState(() {
                _currentIndex = index;
              });

              if (index == 0) {
                await chatProvider.fetchChats();
              } else if (index == _invitesTabIndex) {
                await inviteProvider.fetchInvites();

                if (!mounted) return;
                inviteProvider.markIncomingSeen();
              }
            },
            backgroundColor: Colors.white,
            elevation: 0,
            destinations: [
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: totalUnreadMessages > 0,
                  label: Text(totalUnreadMessages > 99 ? '99+' : '$totalUnreadMessages'),
                  child: const Icon(Icons.chat_bubble_outline_rounded),
                ),
                selectedIcon: Badge(
                  isLabelVisible: totalUnreadMessages > 0,
                  label: Text(totalUnreadMessages > 99 ? '99+' : '$totalUnreadMessages'),
                  child: const Icon(Icons.chat_bubble_rounded),
                ),
                label: 'Chats',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unseenInvites > 0,
                  label: Text(unseenInvites > 99 ? '99+' : '$unseenInvites'),
                  child: const Icon(Icons.mail_outline_rounded),
                ),
                selectedIcon: Badge(
                  isLabelVisible: unseenInvites > 0,
                  label: Text(unseenInvites > 99 ? '99+' : '$unseenInvites'),
                  child: const Icon(Icons.mail_rounded),
                ),
                label: 'Invites',
              ),
              const NavigationDestination(
                icon: Icon(Icons.search_rounded),
                label: 'Search',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

