import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; // Import for date locale
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as path;
import 'package:gal/gal.dart';

import 'models/food_entry.dart';
import 'services/gemini_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Date Formatting for Chinese
  await initializeDateFormatting('zh_HK', null);

  // Initialize Hive
  await Hive.initFlutter();
  
  // Register Adapter
  Hive.registerAdapter(FoodEntryAdapter());
  
  // Open Box
  await Hive.openBox<FoodEntry>('food_entries');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FoodProvider()),
      ],
      child: MaterialApp(
        title: '糖友',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class FoodProvider extends ChangeNotifier {
  final Box<FoodEntry> _box = Hive.box<FoodEntry>('food_entries');
  final GeminiService _geminiService = GeminiService();
  bool _isLoading = false;

  bool get isLoading => _isLoading;
  List<FoodEntry> get entries => _box.values.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  Future<void> analyzeAndSave(File image) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Analyze with Gemini
      final result = await _geminiService.analyzeFood(image);

      // Save Image Locally (App Storage)
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedImage = await image.copy(path.join(appDir.path, fileName));

      // Create Entry
      final entry = FoodEntry(
        id: DateTime.now().toIso8601String(),
        imagePath: savedImage.path,
        fullResponse: result,
        summary: _extractVerdict(result),
        timestamp: DateTime.now(),
        chatHistory: [], // Initialize empty chat history
      );

      // Save to Hive
      await _box.add(entry);

    } catch (e) {
      debugPrint('Error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> analyzeTextAndSave(String text) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Analyze Text with Gemini
      final result = await _geminiService.analyzeText(text);

      // Create Entry (Empty image path for text-only)
      final entry = FoodEntry(
        id: DateTime.now().toIso8601String(),
        imagePath: "", // Empty string for text-only
        fullResponse: result,
        summary: _extractVerdict(result),
        timestamp: DateTime.now(),
        chatHistory: [],
      );

      await _box.add(entry);

    } catch (e) {
      debugPrint('Error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> generateMealPlanAndSave() async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _geminiService.getMealPlan();

      final entry = FoodEntry(
        id: DateTime.now().toIso8601String(),
        imagePath: "MEAL_PLAN", // Special marker
        fullResponse: result,
        summary: "一日三餐建議", // Fixed summary
        timestamp: DateTime.now(),
        chatHistory: [],
      );

      await _box.add(entry);

    } catch (e) {
      debugPrint('Error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> analyzeHealthAndSave(String symptoms) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _geminiService.analyzeHealth(symptoms);

      final entry = FoodEntry(
        id: DateTime.now().toIso8601String(),
        imagePath: "HEALTH_QUERY", // Special marker for health queries
        fullResponse: result,
        summary: "健康諮詢: ${symptoms.length > 10 ? '${symptoms.substring(0, 10)}...' : symptoms}",
        timestamp: DateTime.now(),
        chatHistory: [],
      );

      await _box.add(entry);
    } catch (e) {
      debugPrint('Error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendChatMessage(FoodEntry entry, String message) async {
    _isLoading = true;
    notifyListeners();
    
    // Optimistic Update: Add user message immediately
    entry.chatHistory.add("user:$message");
    await entry.save(); // Save to Hive
    notifyListeners();

    try {
        // Pass history EXCLUDING the just-added message to avoid duplication in API call
        final historyToSend = entry.chatHistory.take(entry.chatHistory.length - 1).toList();
        
        File? imageFile;
        // Check if it's a real image path
        if (entry.imagePath.isNotEmpty && entry.imagePath != "MEAL_PLAN" && entry.imagePath != "HEALTH_QUERY") {
           imageFile = File(entry.imagePath);
        }

        final response = await _geminiService.chatFood(message, historyToSend, image: imageFile);
        
        // Add model response
        entry.chatHistory.add("model:$response");
        await entry.save();

    } catch (e) {
        entry.chatHistory.add("model:錯誤: 無法連接 AI ($e)");
        await entry.save();
    } finally {
        _isLoading = false;
        notifyListeners();
    }
  }

  String _extractVerdict(String response) {
    // Chinese Traditional Heuristics (Prioritize specific labels)
    if (response.contains("非常健康")) return "非常健康";
    if (response.contains("良好")) return "良好";
    if (response.contains("安全")) return "安全";
    if (response.contains("適量")) return "適量";
    if (response.contains("略為不健康")) return "略為不健康";
    if (response.contains("風險高")) return "風險高";
    if (response.contains("極度不建議")) return "極度不建議";
    
    // Fallback/Legacy
    if (response.contains("Safe")) return "Safe";
    if (response.contains("Moderate")) return "Moderate";
    if (response.contains("Risky")) return "Risky";
    
    return "未知";
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('糖友紀錄'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
            child: FilledButton.icon(
              onPressed: () => _generateMealPlan(context),
              icon: const Icon(Icons.restaurant_menu, size: 20),
              label: const Text("三餐建議"),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal.shade50,
                foregroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer<FoodProvider>(
        builder: (context, provider, child) {
          if (provider.entries.isEmpty) {
            return const Center(child: Text('暫無紀錄，請掃描食物！'));
          }
          return ListView.builder(
            itemCount: provider.entries.length,
            itemBuilder: (context, index) {
              final entry = provider.entries[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: entry.imagePath == "MEAL_PLAN" 
                      ? Container(
                          width: 50, height: 50,
                          color: Colors.teal.shade100,
                          child: const Icon(Icons.restaurant_menu, color: Colors.teal),
                        )
                      : entry.imagePath == "HEALTH_QUERY"
                        ? Container(
                            width: 50, height: 50,
                            color: Colors.red.shade100,
                            child: const Icon(Icons.medical_services, color: Colors.deepOrange),
                          )
                        : entry.imagePath.isEmpty
                        ? Container(
                            width: 50, height: 50,
                            color: Colors.orange.shade100,
                            child: const Icon(Icons.edit_note, color: Colors.orange),
                          )
                        : Image.file(
                            File(entry.imagePath),
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image),
                          ),
                  ),
                  title: Text(DateFormat('yyyy年MM月dd日下午h時mm分', 'zh_HK').format(entry.timestamp).replaceAll('下午下午', '下午').replaceAll('上午上午', '上午')), // Fix potential double prefix
                  subtitle: Text(
                    entry.summary,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _getVerdictColor(entry.summary),
                    ),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DetailScreen(entry: entry),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),

      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: "health_btn",
            onPressed: () {
              _showSymptomInputDialog(context);
            },
            label: const Text('問病問診'),
            icon: const Icon(Icons.medical_services),
            backgroundColor: Colors.red.shade100,
            foregroundColor: Colors.deepOrange,
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: "add_food_btn",
            onPressed: () {
              _showImageSourceDialog(context);
            },
            label: const Text('新增食物'),
            icon: const Icon(Icons.add_a_photo),
          ),
        ],
      ),
    );
  }

  void _showSymptomInputDialog(BuildContext context) {
    final TextEditingController textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('問病問診'),
          content: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               const Text("請輸入您的症狀或近期情況："),
               const SizedBox(height: 8),
               TextField(
                controller: textController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: "例如:我最近血糖值是9.2 mmol/L，我最近有眼睛发黄，尿液发红，左边腹部疼痛。请帮我诊断",
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
             ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                if (textController.text.isNotEmpty) {
                  Navigator.pop(context);
                  _showAnalysisDialog(context, null, text: textController.text, isHealthQuery: true);
                }
              },
              child: const Text('分析'),
            ),
          ],
        );
      },
    );
  }

  void _showImageSourceDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('輸入食物名稱'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showTextInputDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('拍照'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(context, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('從相簿選擇'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(context, ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTextInputDialog(BuildContext context) {
    final TextEditingController textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('輸入食物名稱'),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(hintText: "例如：海南雞飯"),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                if (textController.text.isNotEmpty) {
                  Navigator.pop(context);
                  _showAnalysisDialog(context, null, text: textController.text);
                }
              },
              child: const Text('分析'),
            ),
          ],
        );
      },
    );
  }

  void _generateMealPlan(BuildContext context) {
    _showAnalysisDialog(context, null, isMealPlan: true);
  }

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source, imageQuality: 70);
      
      if (pickedFile != null) {
        if (source == ImageSource.camera && await Gal.hasAccess()) {
           try {
             await Gal.putImage(pickedFile.path);
           } catch (e) {
             debugPrint('Failed to save to gallery: $e');
           }
        }

        if (context.mounted) {
          _showAnalysisDialog(context, File(pickedFile.path));
        }
      }
    } catch (e) {
      if (context.mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('選取圖片失敗: $e')),
         );
      }
    }
  }

  void _showAnalysisDialog(BuildContext context, File? image, {String? text, bool isMealPlan = false, bool isHealthQuery = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Trigger analysis immediately
        final provider = Provider.of<FoodProvider>(context, listen: false);
        
        Future<void> task;
        String processingText = "正在分析...";
        
        if (isMealPlan) {
           task = provider.generateMealPlanAndSave();
           processingText = "正在為您規劃一日三餐...";
        } else if (isHealthQuery && text != null) {
           task = provider.analyzeHealthAndSave(text);
           processingText = "正在分析您的健康狀況...";
        } else if (text != null) {
           task = provider.analyzeTextAndSave(text);
           processingText = "正在分析食物...";
        } else if (image != null) {
           task = provider.analyzeAndSave(image);
           processingText = "正在分析圖片...";
        } else {
           task = Future.error("Invalid input");
        }

        task.then((_) {
          if (dialogContext.mounted) {
            Navigator.pop(dialogContext); // Close dialog
          }
        }).catchError((error) {
           if (dialogContext.mounted) {
            Navigator.pop(dialogContext);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('錯誤: $error')),
            );
          }
        });

        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(processingText),
            ],
          ),
        );
      },
    );
  }

  Color _getVerdictColor(String verdict) {
    switch (verdict) {
      case 'Safe':
      case '安全':
      case '非常健康':
      case '良好':
        return Colors.green;
      case 'Moderate':
      case '適量':
      case '略為不健康':
        return Colors.orange;
      case 'Risky':
      case '危險':
      case '風險高':
      case '極度不建議':
        return Colors.red;
      default: return Colors.grey;
    }
  }
}

class DetailScreen extends StatefulWidget {
  final FoodEntry entry;

  const DetailScreen({super.key, required this.entry});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<FoodProvider>(context);

    // Combine initial Analysis + Chat History
    List<Widget> chatWidgets = [
       widget.entry.imagePath == "MEAL_PLAN"
         ? Container(
             width: double.infinity,
             height: 150,
             color: Colors.teal.shade50,
             child: const Center(child: Icon(Icons.restaurant_menu, size: 80, color: Colors.teal)),
           )
         : widget.entry.imagePath == "HEALTH_QUERY"
           ? Container(
               width: double.infinity,
               height: 150,
               color: Colors.red.shade50,
               child: const Center(child: Icon(Icons.medical_services, size: 80, color: Colors.deepOrange)),
             )
         : widget.entry.imagePath.isEmpty
           ? Container(
               width: double.infinity,
               height: 150,
               color: Colors.orange.shade50,
               child: const Center(child: Icon(Icons.edit_note, size: 80, color: Colors.orange)),
             )
           : Image.file(
              File(widget.entry.imagePath),
              width: double.infinity,
              height: 250,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const SizedBox(
                height: 250,
                child: Center(child: Icon(Icons.broken_image, size: 50)),
              ),
            ),
        _buildMessageBubble(widget.entry.fullResponse, isUser: false),
    ];

    for (var msg in widget.entry.chatHistory) {
      if (msg.startsWith("user:")) {
        chatWidgets.add(_buildMessageBubble(msg.substring(5), isUser: true));
      } else if (msg.startsWith("model:")) {
        chatWidgets.add(_buildMessageBubble(msg.substring(6), isUser: false));
      }
    }
    
    // Auto-scroll on new messages
    _scrollToBottom();

    return Scaffold(
      appBar: AppBar(title: const Text('分析與對話')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: chatWidgets,
              ),
            ),
          ),
          if (provider.isLoading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: '想問更多問題？',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: provider.isLoading ? null : () {
                    if (_controller.text.isNotEmpty) {
                      final text = _controller.text;
                      _controller.clear();
                      provider.sendChatMessage(widget.entry, text);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(String text, {required bool isUser}) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? Colors.teal.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: isUser 
          ? Text(text, style: const TextStyle(fontSize: 16))
          : MarkdownBody(data: text, selectable: true),
      ),
    );
  }
}
