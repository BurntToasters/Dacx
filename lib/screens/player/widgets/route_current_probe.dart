import 'package:flutter/widgets.dart';

class RouteCurrentProbe extends StatefulWidget {
  const RouteCurrentProbe({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<RouteCurrentProbe> createState() => _RouteCurrentProbeState();
}

class _RouteCurrentProbeState extends State<RouteCurrentProbe> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.isCurrentOf(context);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
