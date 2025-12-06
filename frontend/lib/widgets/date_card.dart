import 'package:flutter/material.dart';
import '../services/date_proposal_service.dart';
import '../theme/vlvt_colors.dart';
import '../theme/vlvt_text_styles.dart';
import 'vlvt_button.dart';

/// Card widget for displaying a date proposal in chat
class DateCard extends StatelessWidget {
  final DateProposal proposal;
  final String currentUserId;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  const DateCard({
    super.key,
    required this.proposal,
    required this.currentUserId,
    this.onAccept,
    this.onDecline,
    this.onConfirm,
    this.onCancel,
  });

  bool get isProposer => proposal.proposerId == currentUserId;

  Color get _statusColor {
    switch (proposal.status) {
      case 'pending':
        return VlvtColors.gold;
      case 'accepted':
        return VlvtColors.success;
      case 'declined':
        return VlvtColors.error;
      case 'completed':
        return VlvtColors.gold;
      case 'cancelled':
        return VlvtColors.textMuted;
      default:
        return VlvtColors.textSecondary;
    }
  }

  String get _statusText {
    switch (proposal.status) {
      case 'pending':
        return isProposer ? 'Waiting for response' : 'New proposal';
      case 'accepted':
        if (proposal.proposerConfirmed && proposal.recipientConfirmed) {
          return 'Confirmed!';
        } else if (isProposer && proposal.proposerConfirmed) {
          return 'You confirmed - waiting for them';
        } else if (!isProposer && proposal.recipientConfirmed) {
          return 'You confirmed - waiting for them';
        }
        return 'Accepted - Confirm after the date';
      case 'declined':
        return 'Declined';
      case 'completed':
        return 'Date completed!';
      case 'cancelled':
        return 'Cancelled';
      default:
        return proposal.status;
    }
  }

  IconData get _statusIcon {
    switch (proposal.status) {
      case 'pending':
        return Icons.hourglass_empty;
      case 'accepted':
        return Icons.check_circle_outline;
      case 'declined':
        return Icons.cancel_outlined;
      case 'completed':
        return Icons.celebration;
      case 'cancelled':
        return Icons.block;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            VlvtColors.gold.withValues(alpha: 0.15),
            VlvtColors.gold.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VlvtColors.gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: VlvtColors.gold.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: VlvtColors.gold, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isProposer ? 'You proposed a date' : '${proposal.proposerName ?? "They"} proposed a date',
                    style: VlvtTextStyles.labelMedium.copyWith(
                      color: VlvtColors.gold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_statusIcon, size: 14, color: _statusColor),
                      const SizedBox(width: 4),
                      Text(
                        proposal.status.toUpperCase(),
                        style: VlvtTextStyles.caption.copyWith(
                          color: _statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Venue
                Row(
                  children: [
                    Icon(Icons.place, color: VlvtColors.textSecondary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            proposal.placeName,
                            style: VlvtTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (proposal.placeAddress != null)
                            Text(
                              proposal.placeAddress!,
                              style: VlvtTextStyles.caption.copyWith(color: VlvtColors.textMuted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Date and Time
                Row(
                  children: [
                    _buildInfoChip(Icons.event, proposal.formattedDate),
                    const SizedBox(width: 12),
                    _buildInfoChip(Icons.access_time, proposal.formattedTime),
                  ],
                ),

                // Note
                if (proposal.note != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: VlvtColors.background.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.format_quote, color: VlvtColors.textMuted, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            proposal.note!,
                            style: VlvtTextStyles.bodySmall.copyWith(
                              color: VlvtColors.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Status message
                const SizedBox(height: 12),
                Text(
                  _statusText,
                  style: VlvtTextStyles.caption.copyWith(color: _statusColor),
                ),
              ],
            ),
          ),

          // Actions
          if (_showActions)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildActions(),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: VlvtColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VlvtColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: VlvtColors.gold),
          const SizedBox(width: 6),
          Text(text, style: VlvtTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  bool get _showActions {
    // Show accept/decline for recipient on pending proposals
    if (!isProposer && proposal.isPending) return true;

    // Show confirm button for accepted proposals where user hasn't confirmed yet
    if (proposal.isAccepted) {
      if (isProposer && !proposal.proposerConfirmed) return true;
      if (!isProposer && !proposal.recipientConfirmed) return true;
    }

    // Show cancel for proposer on pending/accepted proposals
    if (isProposer && (proposal.isPending || proposal.isAccepted)) return true;

    return false;
  }

  Widget _buildActions() {
    // Recipient actions for pending proposal
    if (!isProposer && proposal.isPending) {
      return Row(
        children: [
          Expanded(
            child: VlvtButton.secondary(
              label: 'Decline',
              onPressed: onDecline,
              icon: Icons.close,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: VlvtButton.primary(
              label: 'Accept',
              onPressed: onAccept,
              icon: Icons.check,
            ),
          ),
        ],
      );
    }

    // Confirm action for accepted proposal
    if (proposal.isAccepted) {
      final canConfirm = (isProposer && !proposal.proposerConfirmed) ||
          (!isProposer && !proposal.recipientConfirmed);

      if (canConfirm) {
        return Row(
          children: [
            if (isProposer) ...[
              Expanded(
                child: VlvtButton.secondary(
                  label: 'Cancel',
                  onPressed: onCancel,
                  icon: Icons.close,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: VlvtButton.primary(
                label: 'Confirm Date Happened',
                onPressed: onConfirm,
                icon: Icons.celebration,
              ),
            ),
          ],
        );
      }
    }

    // Cancel for proposer
    if (isProposer && proposal.isPending) {
      return VlvtButton.secondary(
        label: 'Cancel Proposal',
        onPressed: onCancel,
        icon: Icons.close,
        expanded: true,
      );
    }

    return const SizedBox.shrink();
  }
}
