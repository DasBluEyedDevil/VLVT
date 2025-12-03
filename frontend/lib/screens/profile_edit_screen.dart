import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/profile.dart';
import '../services/profile_api_service.dart';
import '../services/auth_service.dart';
import '../widgets/photo_manager_widget.dart';
import '../widgets/vlvt_input.dart';
import '../widgets/vlvt_button.dart';
import '../theme/vlvt_colors.dart';
import '../theme/vlvt_text_styles.dart';

class ProfileEditScreen extends StatefulWidget {
  final Profile? existingProfile;
  final bool isFirstTimeSetup;

  const ProfileEditScreen({
    super.key,
    this.existingProfile,
    this.isFirstTimeSetup = false,
  });

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _bioController = TextEditingController();
  final _interestController = TextEditingController();
  final _photoManagerKey = GlobalKey<PhotoManagerWidgetState>();

  List<String> _interests = [];
  List<String> _photos = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  void _loadExistingData() {
    if (widget.existingProfile != null) {
      _nameController.text = widget.existingProfile!.name ?? '';
      _ageController.text = widget.existingProfile!.age?.toString() ?? '';
      _bioController.text = widget.existingProfile!.bio ?? '';
      _interests = List.from(widget.existingProfile!.interests ?? []);
      _photos = List.from(widget.existingProfile!.photos ?? []);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _bioController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  void _addInterest() {
    final interest = _interestController.text.trim();
    if (interest.isNotEmpty && !_interests.contains(interest)) {
      setState(() {
        _interests.add(interest);
        _interestController.clear();
      });
    }
  }

  void _removeInterest(String interest) {
    setState(() {
      _interests.remove(interest);
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = context.read<AuthService>();
      final profileService = context.read<ProfileApiService>();
      final userId = authService.userId;

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Filter out local photo markers from the photos list
      final uploadedPhotos = _photos.where((p) => !p.startsWith('local:')).toList();

      final profile = Profile(
        userId: userId,
        name: _nameController.text.trim(),
        age: int.parse(_ageController.text.trim()),
        bio: _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
        interests: _interests.isEmpty ? null : _interests,
        photos: uploadedPhotos.isEmpty ? null : uploadedPhotos,
      );

      Profile updatedProfile;
      if (widget.existingProfile != null) {
        updatedProfile = await profileService.updateProfile(profile);
      } else {
        updatedProfile = await profileService.createProfile(profile);
      }

      // Upload any pending local photos after profile creation
      if (widget.isFirstTimeSetup && _photoManagerKey.currentState != null) {
        final pendingPhotos = _photoManagerKey.currentState!.getPendingLocalPhotos();
        if (pendingPhotos.isNotEmpty) {
          final uploadedPhotoUrls = <String>[];
          for (final photoPath in pendingPhotos) {
            try {
              final result = await profileService.uploadPhoto(photoPath);
              if (result['success'] == true && result['photo'] != null) {
                uploadedPhotoUrls.add(result['photo']['url'] as String);
              }
            } catch (e) {
              debugPrint('Failed to upload photo: $e');
              // Continue with other photos even if one fails
            }
          }

          // Update the profile with the newly uploaded photos
          if (uploadedPhotoUrls.isNotEmpty) {
            final currentPhotos = updatedProfile.photos ?? [];
            updatedProfile = await profileService.updateProfile(
              Profile(
                userId: userId,
                name: updatedProfile.name,
                age: updatedProfile.age,
                bio: updatedProfile.bio,
                interests: updatedProfile.interests,
                photos: [...currentPhotos, ...uploadedPhotoUrls],
              ),
            );
          }

          _photoManagerKey.currentState!.clearPendingLocalPhotos();
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isFirstTimeSetup
              ? 'Profile created successfully!'
              : 'Profile updated successfully!'),
          backgroundColor: VlvtColors.success,
        ),
      );

      Navigator.of(context).pop(updatedProfile);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save profile: ${e.toString()}'),
          backgroundColor: VlvtColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isFirstTimeSetup ? 'Create Your Profile' : 'Edit Profile'),
        automaticallyImplyLeading: !widget.isFirstTimeSetup,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                if (widget.isFirstTimeSetup) ...[
                  Icon(
                    Icons.person_add,
                    size: 80,
                    color: VlvtColors.gold,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome!',
                    style: VlvtTextStyles.displaySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Let\'s set up your profile to get started',
                    style: VlvtTextStyles.bodyMedium.copyWith(
                      color: VlvtColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                ],
                VlvtInput(
                  controller: _nameController,
                  labelText: 'Name *',
                  hintText: 'Enter your name',
                  prefixIcon: Icons.person,
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    if (value.trim().length < 2) {
                      return 'Name must be at least 2 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                VlvtInput(
                  controller: _ageController,
                  labelText: 'Age *',
                  hintText: 'Enter your age',
                  prefixIcon: Icons.cake,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your age';
                    }
                    final age = int.tryParse(value.trim());
                    if (age == null) {
                      return 'Please enter a valid age';
                    }
                    if (age < 18) {
                      return 'You must be at least 18 years old';
                    }
                    if (age > 120) {
                      return 'Please enter a valid age';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                VlvtInput(
                  controller: _bioController,
                  labelText: 'Bio',
                  hintText: 'Tell us about yourself...',
                  prefixIcon: Icons.edit_note,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 24),
                Text(
                  'Interests',
                  style: VlvtTextStyles.labelLarge,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: VlvtInput(
                        controller: _interestController,
                        hintText: 'Add an interest',
                        prefixIcon: Icons.interests,
                        textCapitalization: TextCapitalization.words,
                        onSubmitted: (_) => _addInterest(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: _addInterest,
                      icon: const Icon(Icons.add),
                      tooltip: 'Add interest',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_interests.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _interests.map((interest) {
                      return Chip(
                        label: Text(interest),
                        onDeleted: () => _removeInterest(interest),
                        deleteIcon: const Icon(Icons.close, size: 18),
                      );
                    }).toList(),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: VlvtColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: VlvtColors.border),
                    ),
                    child: Text(
                      'No interests added yet. Add some to help others get to know you!',
                      style: TextStyle(color: VlvtColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 32),
                PhotoManagerWidget(
                  key: _photoManagerKey,
                  initialPhotos: _photos,
                  onPhotosChanged: (photos) {
                    setState(() {
                      _photos = photos;
                    });
                  },
                  maxPhotos: 6,
                  isFirstTimeSetup: widget.isFirstTimeSetup,
                ),
                const SizedBox(height: 32),
                VlvtButton.primary(
                  label: _isLoading
                      ? 'Saving...'
                      : widget.isFirstTimeSetup
                          ? 'Create Profile'
                          : 'Save Changes',
                  onPressed: _isLoading ? null : _saveProfile,
                  icon: Icons.save,
                  loading: _isLoading,
                  expanded: true,
                ),
                if (!widget.isFirstTimeSetup) ...[
                  const SizedBox(height: 12),
                  VlvtButton.secondary(
                    label: 'Cancel',
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    expanded: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
