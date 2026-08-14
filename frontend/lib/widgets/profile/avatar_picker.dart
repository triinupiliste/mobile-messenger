import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_colors.dart';

class AvatarPicker extends StatelessWidget {
  final String? currentImageUrl;
  final File? selectedFile;
  final Function(File) onImageSelected;

  const AvatarPicker({
    super.key,
    this.currentImageUrl,
    this.selectedFile,
    required this.onImageSelected,
  });

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 80);

    if (pickedFile == null) return;

    final extension = pickedFile.path.split('.').last.toLowerCase();
    if (extension != 'jpg' && extension != 'jpeg' && extension != 'png') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only JPEG and PNG images are supported.')),
        );
      }
      return;
    }

    final file = File(pickedFile.path);
    const maxBytes = 5 * 1024 * 1024;
    if (await file.length() > maxBytes) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile pictures must be 5MB or smaller.')),
        );
      }
      return;
    }

    onImageSelected(file);
  }

  void _showPickerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppColors.primary),
                title: const Text('Pick from Gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(context, ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: AppColors.primary),
                title: const Text('Take a Photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(context, ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? backgroundImage;

    if (selectedFile != null) {
      backgroundImage = FileImage(selectedFile!);
    } else if (currentImageUrl != null && currentImageUrl!.isNotEmpty) {
      backgroundImage = NetworkImage(currentImageUrl!);
    }

    return GestureDetector(
      onTap: () => _showPickerOptions(context),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            backgroundImage: backgroundImage,
            child: backgroundImage == null
                ? const Icon(Icons.person, size: 50, color: AppColors.primary)
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}