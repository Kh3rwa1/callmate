import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../config/brand.dart';
import '../data/app_repository.dart';
import '../features/home/home_screen.dart';
import '../features/calls/calls_screen.dart';
import '../features/pipeline/pipeline_screen.dart';
import '../features/more/more_screen.dart';
import '../models/call.dart';
import '../models/contact.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Route names. Keeping them in one place mirrors the web app's route table.
class Routes {
  const Routes._();

  static const home = '/';
  static const pipeline = '/pipeline';
  static const calls = '/calls';
  static const more = '/more';
}

/// Navigates from inside a screen without needing a [BuildContext] route helper.
extension AppNavigator on BuildContext {
  void open(Widget screen) => Navigator.of(this).push(
        MaterialPageRoute(builder: (_) => screen),
      );

  void close() => Navigator.of(this).pop();
}

/// The app frame: four bottom tabs and a shared app bar.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Load the customer book as soon as the shell appears.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppRepository>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      const HomeScreen(),
      const PipelineScreen(),
      const CallsScreen(),
      const MoreScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: _BottomBar(
        index: _index,
        onSelect: (value) => setState(() => _index = value),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onSelect});

  final int index;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_rounded, 'Home'),
      (Icons.view_kanban_rounded, 'Pipeline'),
      (Icons.phone_rounded, 'Calls'),
      (Icons.grid_view_rounded, 'More'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onSelect(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          items[i].$1,
                          size: 23,
                          color: i == index ? AppColors.brand : AppColors.inkSoft,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          items[i].$2,
                          style: AppText.label.copyWith(
                            color: i == index ? AppColors.brand : AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A shared inner page scaffold: back arrow, title and scrollable content.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.showBack = true,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 40),
          children: [child],
        ),
      ),
    );
  }
}

/// Shown while the first load is in flight.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key, this.label = 'Loading…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          const CircularProgressIndicator(color: AppColors.brand),
          const SizedBox(height: AppSpacing.lg),
          Text(label, style: AppText.caption.copyWith(color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}

/// Shown when a load fails, with a way to try again.
class ErrorBlock extends StatelessWidget {
  const ErrorBlock({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: AppSpacing.md),
      child: Column(
        children: [
          const Mascot(mood: MascotMood.confused, size: 76),
          const SizedBox(height: AppSpacing.lg),
          Text(title, style: AppText.title, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: AppText.caption.copyWith(color: AppColors.inkSoft),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: 200,
              child: PrimaryButton(label: 'Try again', onPressed: onRetry),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown when a list has nothing in it yet.
class EmptyBlock extends StatelessWidget {
  const EmptyBlock({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: AppSpacing.md),
      child: Column(
        children: [
          const Mascot(mood: MascotMood.confused, size: 76),
          const SizedBox(height: AppSpacing.lg),
          Text(title, style: AppText.title, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: AppText.caption.copyWith(color: AppColors.inkSoft),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: 220,
              child: PrimaryButton(label: actionLabel!, onPressed: onAction),
            ),
          ],
        ],
      ),
    );
  }
}

/// A short confirmation toast, shown from anywhere.
void showAppToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: AppText.caption.copyWith(color: Colors.white),
      ),
      backgroundColor: AppColors.ink,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      duration: const Duration(milliseconds: 2400),
    ),
  );
}

/// Convenience for a screen that wants the customer on a call.
Contact? contactOf(BuildContext context, String contactId) =>
    context.read<AppRepository>().data.contactById(contactId);

Call? callOf(BuildContext context, String callId) =>
    context.read<AppRepository>().data.callById(callId);

/// The employee's name, used throughout the copy.
String get agentName => AppBrand.employeeName;
