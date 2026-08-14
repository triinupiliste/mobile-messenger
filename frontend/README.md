frontend/
├── pubspec.yaml
└── lib/
    ├── main.dart                          <-- App entry point & MultiProvider scope
    │
    ├── theme/                             <-- Visual styling & design system
    │   ├── app_colors.dart                
    │   └── app_theme.dart                 
    │
    ├── models/                            <-- Data serialization models
    │   ├── user_model.dart                
    │   ├── chat_model.dart                
    │   ├── message_model.dart             
    │   └── invite_model.dart              
    │
    ├── services/                          <-- Backend communication & device APIs
    │   ├── api_service.dart               
    │   ├── socket_service.dart            
    │   └── storage_service.dart           
    │
    ├── providers/                         <-- State management (ChangeNotifier / Provider)
    │   ├── auth_provider.dart             
    │   ├── chat_provider.dart             
    │   └── invite_provider.dart           
    │
    ├── screens/                           <-- Full-page user interfaces
    │   ├── auth/
    │   │   ├── login_screen.dart          
    │   │   └── register_screen.dart       
    │   ├── home/
    │   │   └── home_screen.dart           
    │   ├── chat/
    │   │   ├── chat_list_screen.dart      
    │   │   └── chat_room_screen.dart      
    │   ├── invites/
    │   │   └── invites_screen.dart        
    │   ├── profile/
    │   │   └── profile_screen.dart        
    │   └── search/
    │       └── search_screen.dart         
    │
    └── widgets/                           <-- Reusable UI components
        ├── common/                        
        ├── chat/                          
        └── profile/


what needs to be added:
- app should have settings, where i can choose the theme of the app
- default theme is sunset coral, we could also have calm forest or sth where everything is the same except shades of green
- the default profile icon should be in the strongest theme color
- saving media to phone
