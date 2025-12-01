import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../constants/spacing.dart';
import 'vlvt_card.dart';

/// Base shimmer wrapper for skeleton loading
class SkeletonShimmer extends StatelessWidget {
  final Widget child;

  const SkeletonShimmer({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: child,
    );
  }
}

/// Basic skeleton box
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius ?? Spacing.borderRadiusSm,
      ),
    );
  }
}

/// Profile card skeleton for Discovery screen
class ProfileCardSkeleton extends StatelessWidget {
  const ProfileCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Padding(
        padding: Spacing.paddingMd,
        child: VlvtSurfaceCard(
          elevated: true,
          padding: Spacing.paddingXl,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Profile icon placeholder
              SkeletonBox(
                width: 120,
                height: 120,
                borderRadius: BorderRadius.circular(60),
              ),
              Spacing.verticalLg,
              // Name and age placeholder
              SkeletonBox(
                width: 200,
                height: 32,
                borderRadius: Spacing.borderRadiusSm,
              ),
              Spacing.verticalMd,
              // Bio placeholder (3 lines)
              SkeletonBox(
                width: double.infinity,
                height: 16,
                borderRadius: Spacing.borderRadiusSm,
              ),
              Spacing.verticalSm,
              SkeletonBox(
                width: double.infinity,
                height: 16,
                borderRadius: Spacing.borderRadiusSm,
              ),
              Spacing.verticalSm,
              SkeletonBox(
                width: 200,
                height: 16,
                borderRadius: Spacing.borderRadiusSm,
              ),
              Spacing.verticalLg,
              // Interest chips placeholder
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SkeletonBox(
                    width: 80,
                    height: 32,
                    borderRadius: Spacing.borderRadiusRound,
                  ),
                  Spacing.horizontalSm,
                  SkeletonBox(
                    width: 100,
                    height: 32,
                    borderRadius: Spacing.borderRadiusRound,
                  ),
                  Spacing.horizontalSm,
                  SkeletonBox(
                    width: 90,
                    height: 32,
                    borderRadius: Spacing.borderRadiusRound,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Match list item skeleton for Matches screen
class MatchListItemSkeleton extends StatelessWidget {
  const MatchListItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListTile(
        leading: SkeletonBox(
          width: 50,
          height: 50,
          borderRadius: BorderRadius.circular(25),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(
              width: 150,
              height: 16,
              borderRadius: Spacing.borderRadiusSm,
            ),
            Spacing.verticalXs,
            SkeletonBox(
              width: 200,
              height: 14,
              borderRadius: Spacing.borderRadiusSm,
            ),
          ],
        ),
        trailing: SkeletonBox(
          width: 60,
          height: 12,
          borderRadius: Spacing.borderRadiusSm,
        ),
      ),
    );
  }
}

/// Multiple match list items skeleton
class MatchListSkeleton extends StatelessWidget {
  final int itemCount;

  const MatchListSkeleton({
    super.key,
    this.itemCount = 5,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) => const MatchListItemSkeleton(),
    );
  }
}

/// Message bubble skeleton for Chat screen
class MessageBubbleSkeleton extends StatelessWidget {
  final bool isCurrentUser;

  const MessageBubbleSkeleton({
    super.key,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: SkeletonShimmer(
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment:
                isCurrentUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              SkeletonBox(
                width: 200,
                height: 16,
                borderRadius: Spacing.borderRadiusSm,
              ),
              Spacing.verticalXs,
              SkeletonBox(
                width: 150,
                height: 16,
                borderRadius: Spacing.borderRadiusSm,
              ),
              Spacing.verticalXs,
              SkeletonBox(
                width: 60,
                height: 12,
                borderRadius: Spacing.borderRadiusSm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Multiple message bubbles skeleton
class ChatMessagesSkeleton extends StatelessWidget {
  final int messageCount;

  const ChatMessagesSkeleton({
    super.key,
    this.messageCount = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: Spacing.paddingMd,
      itemCount: messageCount,
      itemBuilder: (context, index) => MessageBubbleSkeleton(
        isCurrentUser: index % 3 == 0,
      ),
    );
  }
}

/// Generic list skeleton
class GenericListSkeleton extends StatelessWidget {
  final int itemCount;
  final double itemHeight;

  const GenericListSkeleton({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 80,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.separated(
        padding: Spacing.paddingMd,
        itemCount: itemCount,
        separatorBuilder: (context, index) => Spacing.verticalSm,
        itemBuilder: (context, index) => SkeletonBox(
          width: double.infinity,
          height: itemHeight,
          borderRadius: Spacing.borderRadiusSm,
        ),
      ),
    );
  }
}

/// Circular skeleton for avatars
class CircularSkeleton extends StatelessWidget {
  final double size;

  const CircularSkeleton({
    super.key,
    this.size = 50,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: SkeletonBox(
        width: size,
        height: size,
        borderRadius: BorderRadius.circular(size / 2),
      ),
    );
  }
}

/// Text line skeleton
class TextLineSkeleton extends StatelessWidget {
  final double? width;
  final double height;

  const TextLineSkeleton({
    super.key,
    this.width,
    this.height = 16,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: SkeletonBox(
        width: width,
        height: height,
        borderRadius: Spacing.borderRadiusSm,
      ),
    );
  }
}
