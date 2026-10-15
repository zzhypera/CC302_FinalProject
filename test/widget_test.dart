import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_cafeteria/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Home screen shows cafeteria content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CampusCafeteriaApp());
    await tester.pumpAndSettle();

    expect(find.text('CAMPUS CAFETERIA'), findsOneWidget);
    expect(find.text('View Menu'), findsOneWidget);
    expect(find.text('Campus Cafeteria'), findsWidgets);

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Menu'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets('Bottom navigation switches between screens', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CampusCafeteriaApp());
    await tester.pumpAndSettle();

    expect(find.text('CAFETERIA MENU'), findsNothing);

    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();

    expect(find.text('CAFETERIA MENU'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const CampusCafeteriaApp());
    await tester.pumpAndSettle();
    expect(find.text('CAFETERIA MENU'), findsOneWidget);
  });

  testWidgets('Floating cart button opens empty cart screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CampusCafeteriaApp());
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Your cart is empty.'), findsNothing);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('MY CART'), findsOneWidget);
    expect(find.text('Your cart is empty.'), findsOneWidget);
  });

  testWidgets('Menu create, edit, and delete survive an app restart', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CampusCafeteriaApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Test Bento');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Rice and chicken',
    );
    await tester.enterText(find.byType(TextFormField).at(2), '99');
    await tester.enterText(
      find.byType(TextFormField).at(3),
      'https://example.com/test-bento.png',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Test Bento'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences
          .getString('campus_cafeteria_foods_v1')!
          .contains('https://example.com/test-bento.png'),
      isTrue,
    );

    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(0))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(3))
          .controller!
          .text,
      isEmpty,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit food').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Updated Bento');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Updated Bento'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const CampusCafeteriaApp());
    await tester.pumpAndSettle();
    expect(find.text('Updated Bento'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete product').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Updated Bento'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const CampusCafeteriaApp());
    await tester.pumpAndSettle();
    expect(find.text('Updated Bento'), findsNothing);
    expect(find.text('Chicken Meal'), findsOneWidget);
  });

  testWidgets('Unsaved add form values restore after an app restart', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CampusCafeteriaApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Draft Noodles');
    await tester.enterText(find.byType(TextFormField).at(1), 'Spicy noodles');
    await tester.enterText(find.byType(TextFormField).at(2), '88');
    await tester.enterText(
      find.byType(TextFormField).at(3),
      'https://example.com/draft-noodles.png',
    );
    final categoryDropdown = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(categoryDropdown);
    await tester.pumpAndSettle();
    await tester.tap(categoryDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snacks').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const CampusCafeteriaApp());
    await tester.pumpAndSettle();
    expect(find.text('Add menu item'), findsOneWidget);

    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(0))
          .controller!
          .text,
      'Draft Noodles',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!
          .text,
      'Spicy noodles',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(2))
          .controller!
          .text,
      '88',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(3))
          .controller!
          .text,
      'https://example.com/draft-noodles.png',
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      'Snacks',
    );

    await tester.tap(find.text('Reset draft'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(0))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      'Meals',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(0))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('Unsaved edit draft does not change its saved record', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CampusCafeteriaApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit food').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Unsubmitted Name',
    );
    await tester.enterText(find.byType(TextFormField).at(2), '123');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const CampusCafeteriaApp());
    await tester.pumpAndSettle();
    expect(find.text('Edit menu item'), findsOneWidget);

    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(0))
          .controller!
          .text,
      'Unsubmitted Name',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(2))
          .controller!
          .text,
      '123',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Chicken Meal'), findsOneWidget);
    expect(find.text('Unsubmitted Name'), findsNothing);
  });

  testWidgets('Cart contents survive an app restart', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CampusCafeteriaApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add to cart').first);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const CampusCafeteriaApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('MY CART'), findsOneWidget);
    expect(find.text('Chicken Meal'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('Menu shows loading, error, and empty data feedback', (
    WidgetTester tester,
  ) async {
    MenuScreen buildMenu({
      bool loading = false,
      String? error,
      List<Food> foods = const [],
    }) => MenuScreen(
      foods: foods,
      isLoading: false,
      isPullingApi: loading,
      hasPulledApi: false,
      apiError: error,
      onFavorite: (_) {},
      onRetry: () async {},
      onDelete: (_) {},
      onAdd: () {},
      onEdit: (_) {},
    );

    await tester.pumpWidget(MaterialApp(home: buildMenu(loading: true)));
    expect(find.text('Loading menu data...'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: buildMenu(error: 'Unable to load foods. Please try again.'),
      ),
    );
    expect(
      find.text('Unable to load foods. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: buildMenu()));
    expect(find.text('No menu items available.'), findsOneWidget);
    expect(find.text('Pull API'), findsOneWidget);
  });
}
