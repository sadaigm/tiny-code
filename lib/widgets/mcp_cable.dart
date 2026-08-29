import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';

/// Patch-cable states for the MCP manager rows (see
/// mcp-manager-design-spec.md): the cable's look *is* the server state.
enum CableState { live, off, dead }

/// The patch-cable rail: a 20×56 vertical wire whose color encodes the
/// server's connection state, with a teal signal dot traveling down the
/// wire while live. Falls back to a static dot when the platform requests
/// reduced motion.
class McpCable extends StatelessWidget {
  const McpCable({super.key, required this.state, this.pulse});

  final CableState state;

  /// Drives the traveling dot. Caller owns the controller (typically a
  /// repeating AnimationController from the row's state). If null or the
  /// platform disables animations, a static dot is shown when live.
  final AnimationController? pulse;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final wireColor = switch (state) {
      CableState.live => theme.tool,
      CableState.off => theme.line,
      CableState.dead => theme.err,
    };

    return SizedBox(
      width: 20,
      height: 56,
      child: Stack(
        children: [
          // The wire.
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 2,
              height: 44,
              decoration: BoxDecoration(
                color: state == CableState.dead ? null : wireColor,
                gradient: state == CableState.dead
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [theme.err, Colors.transparent, theme.err],
                        stops: const [0.4, 0.5, 0.6])
                    : null,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // The signal — travels down the wire when live.
          if (state == CableState.live && pulse != null && !reduceMotion)
            AnimatedBuilder(
              animation: pulse!,
              builder: (context, _) => Positioned(
                left: 7,
                top: 8 + 34 * pulse!.value,
                child: Opacity(
                  opacity: 1.0 - (pulse!.value * pulse!.value),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: theme.tool, shape: BoxShape.circle),
                  ),
                ),
              ),
            ),
          if (state == CableState.live &&
              (pulse == null || reduceMotion))
            Positioned(
              left: 7,
              top: 26,
              child: Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: theme.tool, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }
}
