import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/form_draft_store.dart';

void main() {
  runApp(const CampusCafeteriaApp());
}

class CampusCafeteriaApp extends StatelessWidget {
  const CampusCafeteriaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CartModel(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Campus Cafeteria',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
          useMaterial3: true,
        ),
        home: const MainScreen(),
      ),
    );
  }
}

// FOOD MODEL

class Food {
  final String id;

  final String name;

  final String category;

  final String description;

  final double price;

  final String imageUrl;

  bool isFavorite;

  Food({
    String? id,
    required this.name,

    required this.category,

    required this.description,

    required this.price,

    required this.imageUrl,

    this.isFavorite = false,
  }) : id = id ?? 'food_${name.trim().toLowerCase()}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'description': description,
    'price': price,
    'imageUrl': imageUrl,
    'isFavorite': isFavorite,
  };

  factory Food.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    return Food(
      id: json['id'] as String? ?? 'food_${name.trim().toLowerCase()}',
      name: name,
      category: json['category'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
      imageUrl: json['imageUrl'] as String,
      isFavorite: json['isFavorite'] as bool? ?? false,
    );
  }
}

class CartItem {
  final Food food;
  int quantity;

  CartItem({required this.food, this.quantity = 1});
}

class CartModel extends ChangeNotifier {
  final List<CartItem> _items = [];
  late final Future<void> ready = _restore();

  Future<void> _restore() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString('campus_cafeteria_cart_v1');
      if (saved == null) return;
      final decoded = jsonDecode(saved) as List<dynamic>;
      _items
        ..clear()
        ..addAll(
          decoded.map((entry) {
            final data = entry as Map<String, dynamic>;
            return CartItem(
              food: Food.fromJson(data['food'] as Map<String, dynamic>),
              quantity: (data['quantity'] as num).toInt().clamp(1, 999).toInt(),
            );
          }),
        );
      notifyListeners();
    } catch (_) {
      // Ignore invalid cart data and leave the cart empty.
    }
  }

  Future<void> _save() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'campus_cafeteria_cart_v1',
        jsonEncode(
          _items
              .map(
                (item) => {
                  'food': item.food.toJson(),
                  'quantity': item.quantity,
                },
              )
              .toList(),
        ),
      );
    } catch (_) {
      // Cart remains usable if local storage is unavailable.
    }
  }

  List<CartItem> get items => List.unmodifiable(_items);

  int get totalItemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get totalPrice =>
      _items.fold(0, (sum, item) => sum + item.food.price * item.quantity);

  bool get isEmpty => _items.isEmpty;

  void add(Food food) {
    for (final item in _items) {
      if (item.food.name == food.name) {
        item.quantity += 1;
        notifyListeners();
        _save();
        return;
      }
    }
    _items.add(CartItem(food: food));
    notifyListeners();
    _save();
  }

  void remove(Food food) {
    _items.removeWhere((item) => item.food.name == food.name);
    notifyListeners();
    _save();
  }

  void updateQuantity(Food food, int quantity) {
    for (final item in _items) {
      if (item.food.name == food.name) {
        item.quantity = quantity;
        notifyListeners();
        _save();
        return;
      }
    }
  }

  void clear() {
    _items.clear();
    notifyListeners();
    _save();
  }
}

// FETCH FOODS FROM API (TheMealDB - https://www.themealdb.com)

String _mapMealDbCategory(String category) {
  final value = category.toLowerCase();
  if (value.contains('dessert')) return 'Desserts';
  if (value.contains('side') ||
      value.contains('starter') ||
      value.contains('breakfast')) {
    return 'Snacks';
  }
  return 'Meals';
}

double _mealPrice(String idMeal) {
  final code = int.tryParse(idMeal) ?? 0;
  return (code % 50 + 25).toDouble();
}

List<String> _mealIngredients(Map<String, dynamic> meal) {
  final ingredients = <String>[];
  for (var i = 1; i <= 5; i++) {
    final ingredient = meal['strIngredient$i']?.toString();
    if (ingredient != null && ingredient.trim().isNotEmpty) {
      ingredients.add(ingredient);
    }
  }
  return ingredients;
}

Future<List<Food>> fetchFoodsFromApi() async {
  const letters = ['a', 'c', 'd', 's'];

  final responses = await Future.wait(
    letters.map(
      (letter) => http.get(
        Uri.parse(
          'https://www.themealdb.com/api/json/v1/1/search.php?f=$letter',
        ),
      ),
    ),
  );

  final foods = <Food>[];
  final seenIds = <String>{};

  for (final response in responses) {
    if (response.statusCode != 200) continue;

    final data = jsonDecode(response.body);
    final meals = data['meals'];
    if (meals == null) continue;

    for (final meal in meals) {
      final id = meal['idMeal'].toString();
      if (!seenIds.add(id)) continue;

      final ingredients = _mealIngredients(meal);
      final description = ingredients.isNotEmpty
          ? 'Made with ${ingredients.join(', ')}.'
          : 'A delicious meal from the cafeteria.';

      foods.add(
        Food(
          name: meal['strMeal'].toString(),
          category: _mapMealDbCategory(
            meal['strCategory']?.toString() ?? 'Miscellaneous',
          ),
          description: description,
          price: _mealPrice(id),
          imageUrl: meal['strMealThumb'].toString(),
        ),
      );
    }
  }

  if (foods.isEmpty) {
    throw Exception('Failed to load meals');
  }

  return foods;
}

// SAMPLE FOOD DATA

final List<Food> cafeteriaFoods = [
  Food(
    name: 'Chicken Meal',

    category: 'Meals',

    description: 'Fried chicken served with rice.',

    price: 75,

    imageUrl: 'asset/images/ChickenRice.jpg',
  ),

  Food(
    name: 'Spaghetti',

    category: 'Meals',

    description: 'Sweet-style spaghetti with cheese.',

    price: 60,

    imageUrl: 'asset/images/Spageti.jpg',
  ),

  Food(
    name: 'Fried Rice and Egg',

    category: 'Meals',

    description: 'Fried rice served with a fried egg.',

    price: 50,

    imageUrl: 'asset/images/friedrice.jpg',
  ),

  Food(
    name: 'Ham Sandwich',

    category: 'Snacks',

    description: 'Ham and cheese sandwich.',

    price: 45,

    imageUrl: 'asset/images/hamsandwirc.jpg',
  ),

  Food(
    name: 'Iced Tea',

    category: 'Snacks',

    description: 'Refreshing sweet iced tea.',

    price: 25,

    imageUrl: 'asset/images/icedtea.jpg',
  ),

  Food(
    name: 'Burger',

    category: 'Snacks',

    description: 'Burger with fresh vegetables.',

    price: 55,

    imageUrl: 'asset/images/burger.jpg',
  ),

  Food(
    name: 'French Fries',

    category: 'Snacks',

    description: 'Crispy golden potato fries.',

    price: 35,

    imageUrl: 'asset/images/Fries.jpg',
  ),

  Food(
    name: 'Fruit Salad',

    category: 'Desserts',

    description: 'A refreshing mix of sweet fruits.',

    price: 40,

    imageUrl: 'asset/images/fruitsalad.jpg',
  ),
];

// MAIN SCREEN AND NAVIGATION

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;
  bool _userSelectedTab = false;
  bool _isRestoring = true;
  bool _resumeFormPending = false;
  String? _resumeFoodId;
  bool _resumeFormScheduled = false;

  // Show the built-in cafeteria menu immediately. API meals are added only
  // after the user explicitly pulls them.
  List<Food> foods = cafeteriaFoods
      .map((food) => Food.fromJson(food.toJson()))
      .toList();

  bool isLoading = false;

  bool isPullingApi = false;

  bool hasPulledApi = false;

  String? apiError;

  @override
  void initState() {
    super.initState();
    _restoreAppState(context.read<CartModel>().ready);
  }

  Future<void> _restoreAppState(Future<void> cartReady) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedFoods = preferences.getString('campus_cafeteria_foods_v1');
      final restoredFoods = <Food>[];
      if (savedFoods != null) {
        final decoded = jsonDecode(savedFoods) as List<dynamic>;
        final seenNames = <String>{};
        for (final entry in decoded) {
          final food = Food.fromJson(entry as Map<String, dynamic>);
          if (seenNames.add(food.name.trim().toLowerCase())) {
            restoredFoods.add(food);
          }
        }
      }
      final savedIndex = preferences.getInt('campus_cafeteria_selected_tab');
      final apiWasPulled = preferences.getBool(
        'campus_cafeteria_api_pulled_v1',
      );
      final activeFormRaw = preferences.getString(
        'campus_cafeteria_active_food_form_v1',
      );
      if (activeFormRaw != null) {
        final activeForm = jsonDecode(activeFormRaw) as Map<String, dynamic>;
        _resumeFormPending = true;
        _resumeFoodId = activeForm['foodId'] as String?;
      }
      await cartReady;
      if (!mounted) return;
      setState(() {
        // An empty saved list is valid: the user may have deleted every item.
        if (savedFoods != null) foods = restoredFoods;
        if (!_userSelectedTab && savedIndex != null) {
          selectedIndex = savedIndex.clamp(0, 4).toInt();
        }
        hasPulledApi = apiWasPulled ?? false;
        _isRestoring = false;
      });
      _scheduleFormResume();
    } catch (_) {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  void _scheduleFormResume() {
    if (!_resumeFormPending || _resumeFormScheduled) return;
    _resumeFormScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Food? food;
      if (_resumeFoodId != null) {
        for (final item in foods) {
          if (item.id == _resumeFoodId) {
            food = item;
            break;
          }
        }
        if (food == null) {
          _clearActiveFoodForm();
          return;
        }
      }
      _resumeFormPending = false;
      openFoodForm(food: food);
    });
  }

  Future<void> _saveActiveFoodForm(Food? food) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'campus_cafeteria_active_food_form_v1',
        jsonEncode({'foodId': food?.id}),
      );
    } catch (_) {
      // The form still works if browser storage is unavailable.
    }
  }

  Future<void> _clearActiveFoodForm() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove('campus_cafeteria_active_food_form_v1');
    } catch (_) {
      // Ignore unavailable local storage.
    }
  }

  Future<bool> _persistMenu() async {
    final snapshot = jsonEncode(foods.map((food) => food.toJson()).toList());
    try {
      final preferences = await SharedPreferences.getInstance();
      final foodsSaved = await preferences.setString(
        'campus_cafeteria_foods_v1',
        snapshot,
      );
      if (!foodsSaved) return false;
      return await preferences.setBool(
        'campus_cafeteria_api_pulled_v1',
        hasPulledApi,
      );
    } catch (_) {
      return false;
    }
  }

  void selectTab(int index) {
    _userSelectedTab = true;
    setState(() => selectedIndex = index);
    saveSelectedTab(index);
  }

  Future<void> saveSelectedTab(int index) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt('campus_cafeteria_selected_tab', index);
    } catch (_) {
      // Navigation remains usable if browser storage is unavailable.
    }
  }

  Future<void> loadFoods() async {
    try {
      final apiFoods = await fetchFoodsFromApi();

      if (!mounted) return;

      setState(() {
        // Keep the cafeteria's built-in meals and add API results to them.
        // Matching names are skipped to avoid duplicate menu entries.
        final existingNames = foods
            .map((food) => food.name.trim().toLowerCase())
            .toSet();
        foods.addAll(
          apiFoods.where(
            (food) => existingNames.add(food.name.trim().toLowerCase()),
          ),
        );

        isLoading = false;

        hasPulledApi = true;

        apiError = null;
      });
      await _persistMenu();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isLoading = false;

        apiError = 'Unable to load foods. Please try again.';
      });
    }
  }

  Future<void> pullApiFoods() async {
    if (isPullingApi) return;
    setState(() => isPullingApi = true);
    await loadFoods();
    if (!mounted) return;

    setState(() => isPullingApi = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          apiError == null
              ? 'Pulled ${foods.length} meals from TheMealDB.'
              : 'Could not reach TheMealDB. Check your connection and retry.',
        ),
      ),
    );
  }

  void toggleFavorite(Food food) {
    setState(() {
      food.isFavorite = !food.isFavorite;
    });
    _persistMenu();
  }

  Future<void> openFoodForm({Food? food}) async {
    await _saveActiveFoodForm(food);
    if (!mounted) return;

    final result = await showDialog<Food>(
      context: context,
      builder: (_) => FoodFormDialog(food: food),
    );
    if (result == null) {
      await _clearActiveFoodForm();
      return;
    }
    if (!mounted) return;

    setState(() {
      if (food == null) {
        foods.insert(0, result);
      } else {
        final index = foods.indexOf(food);
        if (index != -1) foods[index] = result;
      }
    });
    final persisted = await _persistMenu();
    if (!mounted) return;

    if (persisted) {
      try {
        await Future.wait(
          FoodFormDialog.draftKeys(food)
              .map((key) => FormDraftStore(key).clear()),
        );
      } catch (_) {
        // A stale draft is preferable to losing the submitted form values.
      }
    }
    await _clearActiveFoodForm();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          persisted
              ? food == null
                    ? 'Food added to the menu.'
                    : 'Food updated.'
              : 'Could not save locally. Your form draft was kept.',
        ),
      ),
    );
  }

  void deleteFood(Food food) {
    setState(() {
      foods.remove(food);
    });
    _persistMenu();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${food.name} deleted from the menu.'),

        action: SnackBarAction(
          label: 'Undo',

          onPressed: () {
            setState(() {
              foods.add(food);
            });
            _persistMenu();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isRestoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pages = [
      HomeScreen(foods: foods, onViewMenu: () => selectTab(1)),

      MenuScreen(
        foods: foods,

        isLoading: isLoading,

        isPullingApi: isPullingApi,

        hasPulledApi: hasPulledApi,

        apiError: apiError,

        onFavorite: toggleFavorite,

        onRetry: pullApiFoods,

        onDelete: deleteFood,

        onAdd: () => openFoodForm(),

        onEdit: (food) => openFoodForm(food: food),
      ),

      FavoritesScreen(foods: foods, onFavorite: toggleFavorite),

      CategoriesScreen(foods: foods, onFavorite: toggleFavorite),

      const AboutScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: pages),

      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,

        currentIndex: selectedIndex,

        selectedItemColor: Colors.green.shade700,

        unselectedItemColor: Colors.grey,

        onTap: (index) {
          selectTab(index);
        },

        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),

          BottomNavigationBarItem(
            icon: Icon(Icons.restaurant_menu),

            label: 'Menu',
          ),

          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),

            label: 'Favorites',
          ),

          BottomNavigationBarItem(
            icon: Icon(Icons.category),

            label: 'Categories',
          ),

          BottomNavigationBarItem(icon: Icon(Icons.info), label: 'About'),
        ],
      ),
      floatingActionButton: Consumer<CartModel>(
        builder: (context, cart, child) {
          return FloatingActionButton(
            onPressed: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const CartScreen()));
            },
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            child: Stack(
              children: [
                const Icon(Icons.shopping_cart, size: 28),
                if (cart.totalItemCount > 0)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${cart.totalItemCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// HOME SCREEN

class HomeScreen extends StatelessWidget {
  final List<Food> foods;

  final VoidCallback onViewMenu;

  const HomeScreen({super.key, required this.foods, required this.onViewMenu});

  @override
  Widget build(BuildContext context) {
    final featuredFood = foods.isNotEmpty ? foods.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CAMPUS CAFETERIA',

          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        centerTitle: true,
      ),

      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 800;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isDesktop)
                Row(
                  children: [
                    Expanded(child: _heroImage(desktop: true)),
                    const SizedBox(width: 36),
                    Expanded(child: _intro(onViewMenu, desktop: true)),
                  ],
                )
              else ...[
                _heroImage(desktop: false),
                const SizedBox(height: 20),
                _intro(onViewMenu),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _infoCard(Icons.fastfood, '${foods.length} Foods', 'Available')),
                  const SizedBox(width: 12),
                  Expanded(child: _infoCard(Icons.favorite, '${foods.where((f) => f.isFavorite).length} Favorites', 'Favorite Items')),
                ],
              ),
              const SizedBox(height: 28),
              const Text("Today's Special", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (featuredFood == null)
                const Text('No menu items available.')
              else if (isDesktop)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Row(
                    children: [
                      Expanded(child: _foodImage(featuredFood, height: 230)),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(featuredFood.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(featuredFood.description),
                              const SizedBox(height: 16),
                              Text('\u20B1${featuredFood.price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                _foodImage(featuredFood, height: 180),
                ListTile(
                  title: Text(featuredFood.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(featuredFood.description),
                  trailing: Text('\u20B1${featuredFood.price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          );

          return SingleChildScrollView(
            padding: EdgeInsets.all(isDesktop ? 32 : 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: content,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _heroImage({required bool desktop}) => AspectRatio(
    aspectRatio: desktop ? 16 / 10 : 16 / 9,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=1200',
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.green.shade100,
          child: const Center(child: Icon(Icons.restaurant, size: 70)),
        ),
      ),
    ),
  );

  Widget _intro(VoidCallback onViewMenu, {bool desktop = false}) => Column(
    crossAxisAlignment: desktop ? CrossAxisAlignment.start : CrossAxisAlignment.start,
    children: [
      Text('Campus Cafeteria', style: TextStyle(fontSize: desktop ? 38 : 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Affordable meals for students and faculty.', style: TextStyle(fontSize: 16)),
      const SizedBox(height: 16),
      SizedBox(
        width: desktop ? null : double.infinity,
        child: ElevatedButton.icon(
          onPressed: onViewMenu,
          icon: const Icon(Icons.restaurant_menu),
          label: const Text('View Menu'),
        ),
      ),
    ],
  );

  Widget _infoCard(IconData icon, String title, String subtitle) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),

        child: Column(
          children: [
            Icon(icon, size: 30, color: Colors.green),

            const SizedBox(height: 8),

            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),

            Text(subtitle),
          ],
        ),
      ),
    );
  }
}

// REUSABLE FOOD IMAGE

Widget _foodImage(Food food, {double height = 120}) {
  return _imageSource(food.imageUrl, height: height);
}

Widget _imageSource(String source, {double height = 120}) {
  final imageSource = source.trim();
  if (imageSource.isEmpty) return _foodImageFallback(height);
  final uri = Uri.tryParse(imageSource);
  final isNetworkImage =
      uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  final image = isNetworkImage
      ? Image.network(
          imageSource,
          width: double.infinity,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _foodImageFallback(height),
        )
      : Image.asset(
          imageSource,
          width: double.infinity,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _foodImageFallback(height),
        );

  return image;
}

Widget _foodImageFallback(double height) {
  return Container(
    width: double.infinity,
    height: height,
    color: Colors.green.shade100,
    alignment: Alignment.center,
    child: const Icon(Icons.fastfood, size: 45, color: Colors.green),
  );
}

// MENU SCREEN

class MenuScreen extends StatelessWidget {
  final List<Food> foods;

  final bool isLoading;

  final bool isPullingApi;

  final bool hasPulledApi;

  final String? apiError;

  final ValueChanged<Food> onFavorite;

  final Future<void> Function() onRetry;

  final ValueChanged<Food> onDelete;

  final VoidCallback onAdd;

  final ValueChanged<Food> onEdit;

  const MenuScreen({
    super.key,

    required this.foods,

    required this.isLoading,

    required this.isPullingApi,

    required this.hasPulledApi,

    required this.apiError,

    required this.onFavorite,

    required this.onRetry,

    required this.onDelete,

    required this.onAdd,

    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (isLoading || isPullingApi) {
      body = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading menu data...'),
          ],
        ),
      );
    } else if (apiError != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              const Icon(Icons.cloud_off_outlined, size: 44),
              const SizedBox(height: 12),
              Text(apiError!, textAlign: TextAlign.center),

              const SizedBox(height: 12),

              ElevatedButton.icon(
                onPressed: onRetry,

                icon: const Icon(Icons.refresh),

                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else if (foods.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.restaurant_menu_outlined,
                size: 48,
                color: Colors.green,
              ),
              const SizedBox(height: 12),
              const Text(
                'No menu items available.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Add a food item or pull meals from the API.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.download),
                label: const Text('Pull API'),
              ),
            ],
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: onRetry,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),

          itemCount: foods.length,

          itemBuilder: (context, index) {
            final food = foods[index];

            return Card(
              margin: const EdgeInsets.only(bottom: 12),

              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.all(10),

                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),

                      child: SizedBox(
                        width: 85,

                        height: 100,

                        child: _foodImage(food),
                      ),
                    ),

                    title: Text(
                      food.name,

                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),

                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(food.category),

                          Text(food.description),

                          const SizedBox(height: 5),

                          Text(
                            '₱${food.price.toStringAsFixed(0)}',

                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Edit food',
                        onPressed: () => onEdit(food),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Toggle favorite',

                        onPressed: () {
                          final wasFavorite = food.isFavorite;

                          onFavorite(food);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                wasFavorite
                                    ? '${food.name} removed from Favorites'
                                    : '${food.name} added to Favorites',
                              ),

                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },

                        icon: Icon(
                          food.isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,

                          color: food.isFavorite ? Colors.red : Colors.grey,
                        ),
                      ),

                      IconButton(
                        tooltip: 'Delete product',

                        onPressed: () {
                          showDialog<void>(
                            context: context,

                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Delete Product?'),

                              content: Text(
                                'Are you sure you want to delete "${food.name}"?',
                              ),

                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),

                                  child: const Text('Cancel'),
                                ),

                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(dialogContext);

                                    onDelete(food);
                                  },

                                  child: const Text(
                                    'Delete',

                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },

                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                      ),

                      IconButton(
                        tooltip: 'Add to cart',

                        onPressed: () {
                          context.read<CartModel>().add(food);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${food.name} added to cart.'),

                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },

                        icon: const Icon(
                          Icons.shopping_cart,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('CAFETERIA MENU'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Pull data from TheMealDB',
            onPressed: isPullingApi ? null : onRetry,
            icon: isPullingApi
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined),
          ),
          IconButton(
            tooltip: 'Add food',
            onPressed: onAdd,
            icon: const Icon(Icons.add),
          ),
        ],
      ),

      body: body,
    );
  }
}

class FoodFormDialog extends StatefulWidget {
  final Food? food;

  static String draftKey(Food? food) =>
      'campus_cafeteria_food_draft_v2_${food?.id ?? 'new'}';

  static String legacyDraftKey(Food? food) =>
      'cafeteria_food_draft_${food?.name.trim().toLowerCase() ?? 'new'}';

  static List<String> draftKeys(Food? food) =>
      {draftKey(food), legacyDraftKey(food)}.toList();

  const FoodFormDialog({super.key, this.food});

  @override
  State<FoodFormDialog> createState() => _FoodFormDialogState();
}

class _FoodFormDialogState extends State<FoodFormDialog>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _imageController;
  late String _category;
  bool _restoringDraft = true;
  bool _userEdited = false;
  bool _submitted = false;
  Future<void> _draftWrites = Future<void>.value();
  Timer? _draftDebounce;

  FormDraftStore get _draftStore =>
      FormDraftStore(FoodFormDialog.draftKey(widget.food));

  static const _categories = ['Meals', 'Snacks', 'Desserts'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final food = widget.food;
    _nameController = TextEditingController(text: food?.name ?? '');
    _descriptionController = TextEditingController(
      text: food?.description ?? '',
    );
    _priceController = TextEditingController(
      text: food?.price.toStringAsFixed(0) ?? '',
    );
    _imageController = TextEditingController(text: food?.imageUrl ?? '');
    _category = food != null && _categories.contains(food.category)
        ? food.category
        : _categories.first;
    _nameController.addListener(_onFieldChanged);
    _descriptionController.addListener(_onFieldChanged);
    _priceController.addListener(_onFieldChanged);
    _imageController.addListener(_onFieldChanged);
    _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    try {
      final draft =
          await _draftStore.load() ??
          await FormDraftStore(FoodFormDialog.legacyDraftKey(widget.food))
              .load();
      if (draft != null && mounted && !_userEdited) {
        _nameController.text = draft['name'] as String? ?? _nameController.text;
        _descriptionController.text =
            draft['description'] as String? ?? _descriptionController.text;
        _priceController.text =
            draft['price'] as String? ?? _priceController.text;
        _imageController.text =
            draft['imageUrl'] as String? ?? _imageController.text;
        final category = draft['category'] as String?;
        if (category != null && _categories.contains(category) && mounted) {
          setState(() => _category = category);
        }
      }
    } catch (_) {
      // Ignore an unavailable or malformed draft and keep the form usable.
    } finally {
      _restoringDraft = false;
      if (_userEdited) _scheduleDraftSave();
    }
  }

  void _onFieldChanged() {
    if (_restoringDraft) return;
    _userEdited = true;
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 400), () {
      _flushDraft();
    });
  }

  Future<void> _flushDraft() {
    _draftDebounce?.cancel();
    _draftDebounce = null;
    if (!_userEdited || _submitted) return _draftWrites;

    final draft = <String, dynamic>{
      'name': _nameController.text,
      'description': _descriptionController.text,
      'price': _priceController.text,
      'imageUrl': _imageController.text,
      'category': _category,
    };
    _draftWrites = _draftWrites.then((_) => _draftStore.save(draft)).catchError(
      (Object _) {
        // Keep editing even if browser storage is unavailable.
      },
    );
    return _draftWrites;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _flushDraft();
    }
  }

  Future<void> _resetDraft() async {
    _draftDebounce?.cancel();
    _draftDebounce = null;
    _restoringDraft = true;
    try {
      await _draftWrites;
      await Future.wait(
        FoodFormDialog.draftKeys(widget.food)
            .map((key) => FormDraftStore(key).clear()),
      );
      if (!mounted) return;
      _nameController.text = widget.food?.name ?? '';
      _descriptionController.text = widget.food?.description ?? '';
      _priceController.text = widget.food?.price.toStringAsFixed(0) ?? '';
      _imageController.text = widget.food?.imageUrl ?? '';
      setState(() {
        _category =
            widget.food != null && _categories.contains(widget.food!.category)
            ? widget.food!.category
            : _categories.first;
      });
      _userEdited = false;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not clear the saved draft.')),
        );
      }
    } finally {
      _restoringDraft = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftDebounce?.cancel();
    _flushDraft();
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await _flushDraft();
    if (!mounted) return;
    final previous = widget.food;
    _submitted = true;
    Navigator.pop(
      context,
      Food(
        id: previous?.id ?? 'food_${DateTime.now().microsecondsSinceEpoch}',
        name: _nameController.text.trim(),
        category: _category,
        description: _descriptionController.text.trim(),
        price: double.parse(_priceController.text.trim()),
        imageUrl: _imageController.text.trim().isEmpty
            ? previous?.imageUrl ?? 'asset/images/ChickenRice.jpg'
            : _imageController.text.trim(),
        isFavorite: previous?.isFavorite ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.food == null ? 'Add menu item' : 'Edit menu item'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Food name'),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a food name'
                      : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _category = value);
                    _onFieldChanged();
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    alignLabelWithHint: true,
                  ),
                  minLines: 4,
                  maxLines: 6,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a description'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(labelText: 'Price (₱)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    final price = double.tryParse(value?.trim() ?? '');
                    return price == null || price <= 0
                        ? 'Enter a price above 0'
                        : null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _imageController,
                  decoration: const InputDecoration(
                    labelText: 'Image URL (optional)',
                    hintText: 'https://example.com/image.jpg',
                    helperText: 'Paste a direct link to an image.',
                  ),
                  keyboardType: TextInputType.url,
                  validator: (value) {
                    final source = value?.trim() ?? '';
                    if (source.isEmpty || source.startsWith('asset/')) {
                      return null;
                    }
                    final uri = Uri.tryParse(source);
                    return uri == null ||
                            !['http', 'https'].contains(uri.scheme) ||
                            uri.host.isEmpty
                        ? 'Enter a valid image URL.'
                        : null;
                  },
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _imageController,
                  builder: (context, value, child) {
                    final source = value.text.trim();
                    if (source.isEmpty) {
                      return Container(
                        height: 120,
                        width: double.infinity,
                        color: Colors.green.shade50,
                        alignment: Alignment.center,
                        child: const Text('Image preview'),
                      );
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        height: 120,
                        width: double.infinity,
                        child: _imageSource(source, height: 120),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _resetDraft, child: const Text('Reset draft')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// FAVORITES SCREEN

class FavoritesScreen extends StatelessWidget {
  final List<Food> foods;

  final ValueChanged<Food> onFavorite;

  const FavoritesScreen({
    super.key,

    required this.foods,

    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final favorites = foods.where((food) => food.isFavorite).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('FAVORITE FOODS')),

      body: favorites.isEmpty
          ? const Center(child: Text('No favorite foods yet.'))
          : ListView.builder(
              itemCount: favorites.length,

              itemBuilder: (context, index) {
                final food = favorites[index];

                return ListTile(
                  leading: SizedBox(width: 65, child: _foodImage(food)),

                  title: Text(food.name),

                  subtitle: Text(
                    '${food.category} • ₱${food.price.toStringAsFixed(0)}',
                  ),

                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,

                    children: [
                      IconButton(
                        icon: const Icon(Icons.favorite, color: Colors.red),

                        onPressed: () => onFavorite(food),
                      ),

                      IconButton(
                        icon: const Icon(
                          Icons.shopping_cart,
                          color: Colors.green,
                        ),
                        onPressed: () {
                          context.read<CartModel>().add(food);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${food.name} added to cart.'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// CATEGORIES SCREEN

class CategoriesScreen extends StatefulWidget {
  final List<Food> foods;

  final ValueChanged<Food> onFavorite;

  const CategoriesScreen({
    super.key,

    required this.foods,

    required this.onFavorite,
  });

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String selectedCategory = 'All';

  final categories = ['All', 'Meals', 'Snacks', 'Desserts'];

  @override
  void initState() {
    super.initState();
    _restoreCategory();
  }

  Future<void> _restoreCategory() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString('campus_cafeteria_category_v1');
      if (!mounted || saved == null || !categories.contains(saved)) return;
      setState(() => selectedCategory = saved);
    } catch (_) {
      // Keep the default category when preferences are unavailable.
    }
  }

  Future<void> _saveCategory(String category) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('campus_cafeteria_category_v1', category);
    } catch (_) {
      // Filtering remains available for this session.
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredFoods = selectedCategory == 'All'
        ? widget.foods
        : widget.foods
              .where((food) => food.category == selectedCategory)
              .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('FOOD CATEGORIES')),

      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,

            padding: const EdgeInsets.all(8),

            child: Row(
              children: categories.map((category) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),

                  child: ChoiceChip(
                    label: Text(category),

                    selected: selectedCategory == category,

                    onSelected: (_) {
                      setState(() {
                        selectedCategory = category;
                      });
                      _saveCategory(category);
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          Expanded(
            child: ListView.builder(
              itemCount: filteredFoods.length,

              itemBuilder: (context, index) {
                final food = filteredFoods[index];

                return ListTile(
                  leading: SizedBox(width: 65, child: _foodImage(food)),

                  title: Text(food.name),

                  subtitle: Text(
                    '${food.category} • ₱${food.price.toStringAsFixed(0)}',
                  ),

                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,

                    children: [
                      IconButton(
                        icon: Icon(
                          food.isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,

                          color: food.isFavorite ? Colors.red : Colors.grey,
                        ),

                        onPressed: () {
                          widget.onFavorite(food);

                          setState(() {});
                        },
                      ),

                      IconButton(
                        icon: const Icon(
                          Icons.shopping_cart,
                          color: Colors.green,
                        ),
                        onPressed: () {
                          context.read<CartModel>().add(food);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${food.name} added to cart.'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// CART SCREEN

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MY CART'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: Consumer<CartModel>(
              builder: (context, cart, child) {
                if (cart.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 80,
                          color: Colors.green,
                        ),
                        SizedBox(height: 16),
                        Text('Your cart is empty.'),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: cart.items.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = cart.items[index];
                    return _CartItemTile(item: item);
                  },
                );
              },
            ),
          ),
          Consumer<CartModel>(
            builder: (context, cart, child) {
              if (cart.isEmpty) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total:', style: TextStyle(fontSize: 18)),
                        Text(
                          '₱${cart.totalPrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Checkout successful! Total: ₱${cart.totalPrice.toStringAsFixed(0)}',
                              ),
                              backgroundColor: Colors.green.shade700,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          cart.clear();
                          Navigator.of(context)
                              .popUntil((route) => route.isFirst);
                        },
                        icon: const Icon(Icons.payment),
                        label: const Text('Checkout'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;

  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartModel>();

    return Card(
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 65,
            height: 85,
            child: _foodImage(item.food, height: 85),
          ),
        ),
        title: Text(
          item.food.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '₱${item.food.price.toStringAsFixed(0)} x ${item.quantity}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove, size: 20, color: Colors.green),
              onPressed: () {
                if (item.quantity > 1) {
                  cart.updateQuantity(item.food, item.quantity - 1);
                } else {
                  cart.remove(item.food);
                }
              },
            ),
            Text(
              item.quantity.toString(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 20, color: Colors.green),
              onPressed: () =>
                  cart.updateQuantity(item.food, item.quantity + 1),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20, color: Colors.red),
              onPressed: () => cart.remove(item.food),
            ),
          ],
        ),
      ),
    );
  }
}

// ABOUT SCREEN

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ABOUT CAFETERIA')),

      body: ListView(
        padding: const EdgeInsets.all(20),

        children: [
          const Icon(Icons.restaurant, size: 90, color: Colors.green),

          const SizedBox(height: 16),

          const Text(
            'Campus Cafeteria',

            textAlign: TextAlign.center,

            style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          const Text(
            'Affordable and convenient meals for students and faculty.',

            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 30),

          const ListTile(
            leading: Icon(Icons.access_time, color: Colors.green),

            title: Text('Opening Hours'),

            subtitle: Text('7:00 AM – 6:00 PM'),
          ),

          const ListTile(
            leading: Icon(Icons.location_on, color: Colors.green),

            title: Text('Location'),

            subtitle: Text('Main Campus Cafeteria'),
          ),

          const ListTile(
            leading: Icon(Icons.phone, color: Colors.green),

            title: Text('Contact'),

            subtitle: Text('0912-345-6789'),
          ),
        ],
      ),
    );
  }
}
