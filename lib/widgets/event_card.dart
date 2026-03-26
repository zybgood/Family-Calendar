import 'package:flutter/material.dart';


class EventCard extends StatelessWidget {
  final Color color;
  final String category;
  final String title;
  final String timeRange;
  final List<String> participants;
  final String? subtitle;
  final Widget? trailingIcon;
  final VoidCallback? onTap;

  const EventCard({
    Key? key,
    required this.color,
    required this.category,
    required this.title,
    required this.timeRange,
    required this.participants,
    this.subtitle,
    this.trailingIcon,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final card = Container(
      constraints: const BoxConstraints(maxWidth: 282),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.toUpperCase(),
                      style: TextStyle(
                        color: _fadedColorFor(color),
                        fontSize: 12,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: TextStyle(
                        color: _primaryTextColorFor(color),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      timeRange,
                      style: TextStyle(
                        color: _fadedColorFor(color),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailingIcon != null) trailingIcon!,
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ..._buildParticipantAvatars(),
              if (subtitle != null) const SizedBox(width: 8),
              if (subtitle != null)
                Flexible(
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      color: _fadedColorFor(color),
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return card;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: card,
    );
  }

  List<Widget> _buildParticipantAvatars() {
    const double size = 32;
    const double overlap = 10;

    return participants.asMap().entries.map((entry) {
      final index = entry.key;
      final imageUrl = entry.value;

      return Transform.translate(
        offset: Offset(index == 0 ? 0 : -overlap, 0),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipOval(
            child: imageUrl.isNotEmpty
                ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFFF1F5F9),
                child: const Icon(
                  Icons.person,
                  size: 18,
                  color: Colors.grey,
                ),
              ),
            )
                : Container(
              color: const Color(0xFFF1F5F9),
              child: const Icon(
                Icons.person,
                size: 18,
                color: Colors.grey,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }


  Color _fadedColorFor(Color c) {
    return c.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70;
  }

  Color _primaryTextColorFor(Color c) {
    return c.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }
}
