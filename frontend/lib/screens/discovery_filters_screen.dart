import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/discovery_preferences_service.dart';
import '../config/app_colors.dart';
import '../constants/text_styles.dart';

class DiscoveryFiltersScreen extends StatefulWidget {
  const DiscoveryFiltersScreen({super.key});

  @override
  State<DiscoveryFiltersScreen> createState() => _DiscoveryFiltersScreenState();
}

class _DiscoveryFiltersScreenState extends State<DiscoveryFiltersScreen> {
  late int _minAge;
  late int _maxAge;
  late double _maxDistance;
  late List<String> _selectedInterests;

  // Available interests
  final List<String> _availableInterests = [
    'Travel',
    'Music',
    'Sports',
    'Movies',
    'Reading',
    'Cooking',
    'Gaming',
    'Fitness',
    'Art',
    'Photography',
    'Dancing',
    'Hiking',
    'Technology',
    'Fashion',
    'Food',
    'Pets',
    'Yoga',
    'Wine',
    'Coffee',
    'Nature',
  ];

  @override
  void initState() {
    super.initState();
    final prefsService = context.read<DiscoveryPreferencesService>();
    final filters = prefsService.filters;

    _minAge = filters.minAge;
    _maxAge = filters.maxAge;
    _maxDistance = filters.maxDistance;
    _selectedInterests = List.from(filters.selectedInterests);
  }

  Future<void> _applyFilters() async {
    final prefsService = context.read<DiscoveryPreferencesService>();
    final newFilters = DiscoveryFilters(
      minAge: _minAge,
      maxAge: _maxAge,
      maxDistance: _maxDistance,
      selectedInterests: _selectedInterests,
    );

    await prefsService.updateFilters(newFilters);

    if (mounted) {
      Navigator.pop(context, true); // Return true to indicate filters changed
    }
  }

  Future<void> _clearFilters() async {
    final prefsService = context.read<DiscoveryPreferencesService>();
    await prefsService.clearFilters();

    setState(() {
      _minAge = 18;
      _maxAge = 99;
      _maxDistance = 50.0;
      _selectedInterests.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Filters cleared', style: TextStyle(color: Colors.white)),
          backgroundColor: AppColors.info(context),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discovery Filters'),
        actions: [
          TextButton(
            onPressed: _clearFilters,
            child: Text(
              'Clear All',
              style: TextStyle(color: AppColors.textOnPrimary),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Age Range Section
              Text(
                'Age Range',
                style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary(context)),
              ),
              const SizedBox(height: 8),
              Card(
                color: AppColors.surface(context),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$_minAge - $_maxAge years',
                            style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textPrimary(context)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      RangeSlider(
                        values: RangeValues(
                          _minAge.toDouble(),
                          _maxAge.toDouble(),
                        ),
                        min: 18,
                        max: 99,
                        divisions: 81,
                        labels: RangeLabels(
                          _minAge.toString(),
                          _maxAge.toString(),
                        ),
                        onChanged: (RangeValues values) {
                          setState(() {
                            _minAge = values.start.round();
                            _maxAge = values.end.round();
                          });
                        },
                        activeColor: AppColors.primaryLight,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Distance Section
              Text(
                'Maximum Distance',
                style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary(context)),
              ),
              const SizedBox(height: 8),
              Card(
                color: AppColors.surface(context),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_maxDistance.round()} km',
                            style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textPrimary(context)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: _maxDistance,
                        min: 1,
                        max: 200,
                        divisions: 199,
                        label: '${_maxDistance.round()} km',
                        onChanged: (double value) {
                          setState(() {
                            _maxDistance = value;
                          });
                        },
                        activeColor: AppColors.primaryLight,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Interests Section
              Text(
                'Interests',
                style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary(context)),
              ),
              const SizedBox(height: 8),
              Card(
                color: AppColors.surface(context),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedInterests.isEmpty
                            ? 'No interests selected'
                            : '${_selectedInterests.length} selected',
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary(context)),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availableInterests.map((interest) {
                          final isSelected = _selectedInterests.contains(interest);
                          return FilterChip(
                            label: Text(interest),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedInterests.add(interest);
                                } else {
                                  _selectedInterests.remove(interest);
                                }
                              });
                            },
                            selectedColor: AppColors.primaryLight.withOpacity(0.2),
                            checkmarkColor: AppColors.primaryLight,
                            labelStyle: TextStyle(
                              color: isSelected ? AppColors.primaryLight : AppColors.textPrimary(context),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Apply Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _applyFilters,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.primaryLight,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    'Apply Filters',
                    style: AppTextStyles.button,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Info text
              Center(
                child: Text(
                  'Filters help you find more compatible matches',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary(context)),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
