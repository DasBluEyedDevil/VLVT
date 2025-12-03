import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/profile_api_service.dart';
import '../theme/vlvt_colors.dart';
import 'vlvt_button.dart';


/// Simplified Photo Manager Widget for Profile Photos
/// Displays up to 6 photos in a grid with upload/delete functionality
class PhotoManagerWidget extends StatefulWidget {
  final List<String> initialPhotos;
  final Function(List<String>) onPhotosChanged;
  final int maxPhotos;
  /// When true, photos are queued locally instead of uploaded immediately.
  /// Use getPendingLocalPhotos() to retrieve paths for later upload.
  final bool isFirstTimeSetup;

  const PhotoManagerWidget({
    super.key,
    required this.initialPhotos,
    required this.onPhotosChanged,
    this.maxPhotos = 6,
    this.isFirstTimeSetup = false,
  });

  @override
  State<PhotoManagerWidget> createState() => PhotoManagerWidgetState();
}

class PhotoManagerWidgetState extends State<PhotoManagerWidget> {
  late List<String> _photos;
  /// Local file paths queued for upload (used in first-time setup mode)
  final List<String> _pendingLocalPhotos = [];
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _photos = List.from(widget.initialPhotos);
  }

  /// Returns list of local file paths that need to be uploaded.
  /// Call this after profile creation to get photos to upload.
  List<String> getPendingLocalPhotos() => List.unmodifiable(_pendingLocalPhotos);

  /// Clears the pending local photos list after successful upload
  void clearPendingLocalPhotos() {
    setState(() {
      _pendingLocalPhotos.clear();
    });
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (image == null) return;
      if (!mounted) return;

      // In first-time setup mode, queue photo locally instead of uploading
      if (widget.isFirstTimeSetup) {
        setState(() {
          _pendingLocalPhotos.add(image.path);
        });
        // Notify parent with a special marker for local files
        widget.onPhotosChanged([..._photos, ..._pendingLocalPhotos.map((p) => 'local:$p')]);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo added - will be uploaded when you save your profile'),
              backgroundColor: Colors.blue,
            ),
          );
        }
        return;
      }

      setState(() => _isUploading = true);

      final profileService = context.read<ProfileApiService>();
      final result = await profileService.uploadPhoto(image.path);

      if (result['success'] == true && result['photo'] != null) {
        final photoUrl = result['photo']['url'] as String;
        setState(() {
          _photos.add(photoUrl);
          _isUploading = false;
        });
        widget.onPhotosChanged(_photos);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo uploaded successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload photo: $e')),
        );
      }
    }
  }

  Future<void> _deletePhoto(String photoUrl, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo'),
        content: const Text('Are you sure you want to delete this photo?'),
        actions: [
          VlvtButton.text(
            label: 'Cancel',
            onPressed: () => Navigator.pop(context, false),
          ),
          VlvtButton.danger(
            label: 'Delete',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    // Optimistic UI: Remove photo immediately
    final deletedPhoto = photoUrl;
    final deletedIndex = index;

    setState(() {
      _photos.removeAt(index);
    });
    widget.onPhotosChanged(_photos);

    try {
      // Extract photo ID from URL
      final photoId = photoUrl.split('/').last.split('.').first.split('_').last;
      final profileService = context.read<ProfileApiService>();
      await profileService.deletePhoto(photoId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo deleted successfully'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Revert optimistic update on failure
      setState(() {
        _photos.insert(deletedIndex, deletedPhoto);
      });
      widget.onPhotosChanged(_photos);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPhotoSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadPhoto(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the appropriate image widget for local or network photos
  Widget _buildPhotoImage(String photoPath, int index) {
    // Check if this is a pending local photo
    final pendingIndex = index - _photos.length;
    if (pendingIndex >= 0 && pendingIndex < _pendingLocalPhotos.length) {
      // Local file
      return Image.file(
        File(_pendingLocalPhotos[pendingIndex]),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          color: VlvtColors.surface,
          child: Icon(Icons.broken_image, color: VlvtColors.textMuted),
        ),
      );
    }

    // Network image (uploaded photo)
    return Image.network(
      photoPath.startsWith('http')
          ? photoPath
          : '${context.read<ProfileApiService>().baseUrl}$photoPath',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: VlvtColors.surface,
        child: Icon(Icons.broken_image, color: VlvtColors.textMuted),
      ),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: VlvtColors.surface,
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
    );
  }

  /// Handles deletion of photos (both pending local and uploaded)
  void _handlePhotoDelete(int index) {
    final pendingIndex = index - _photos.length;
    if (pendingIndex >= 0 && pendingIndex < _pendingLocalPhotos.length) {
      // Delete pending local photo (no confirmation needed, not uploaded yet)
      setState(() {
        _pendingLocalPhotos.removeAt(pendingIndex);
      });
      widget.onPhotosChanged([..._photos, ..._pendingLocalPhotos.map((p) => 'local:$p')]);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo removed'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 1),
        ),
      );
    } else {
      // Delete uploaded photo
      _deletePhoto(_photos[index], index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPhotos = _photos.length + _pendingLocalPhotos.length;
    final canAddMore = totalPhotos < widget.maxPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Photos ($totalPhotos/${widget.maxPhotos})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Add up to 6 photos. First photo will be your profile picture.',
          style: TextStyle(fontSize: 12, color: VlvtColors.textMuted),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: canAddMore ? totalPhotos + 1 : totalPhotos,
          itemBuilder: (context, index) {
            if (index == totalPhotos && canAddMore) {
              // Add photo button
              return GestureDetector(
                onTap: _isUploading ? null : _showPhotoSourceDialog,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: VlvtColors.borderStrong, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _isUploading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate, size: 32, color: VlvtColors.textMuted),
                            const SizedBox(height: 4),
                            Text('Add Photo', style: TextStyle(fontSize: 10, color: VlvtColors.textMuted)),
                          ],
                        ),
                ),
              );
            }

            // Get the photo path (either from _photos or _pendingLocalPhotos)
            final isLocalPhoto = index >= _photos.length;
            final photoPath = isLocalPhoto
                ? _pendingLocalPhotos[index - _photos.length]
                : _photos[index];

            // Photo tile
            return Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildPhotoImage(photoPath, index),
                ),
                if (index == 0)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Main',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
                // Show "Pending" badge for local photos not yet uploaded
                if (isLocalPhoto)
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Pending',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _handlePhotoDelete(index),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (_photos.isEmpty && _pendingLocalPhotos.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange, width: 2),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Add at least one photo to complete your profile',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
