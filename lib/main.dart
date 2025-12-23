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

  // New - Streaming Analysis
  Future<FoodEntry> analyzeFoodStreamed(File image) async {
    final entry = FoodEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imagePath: image.path,
      fullResponse: "",
      summary: "正在分析...",
      timestamp: DateTime.now(),
      chatHistory: ["model:正在分析食物成分..."],
    );
     // _entries.insert(0, entry); // Error: _entries not defined, use _box
     await _box.add(entry);
     notifyListeners();
    
    // Start background stream
    _streamEntryAnalysis(entry, image);
    return entry;
  }

  Future<void> _streamEntryAnalysis(FoodEntry entry, File image) async {
      final prompt = "I am a 60 year old man live in Hong Kong, I have type 2 diabetes and have also had my gallbladder removed. My name is 張耀倫, you can call me 耀倫. You are an expert in nutrition for people with type 2 diabetes and post-cholecystectomy (gallbladder removal). I will upload an image of a food item or a food menu. \n\nPlease:\n1. Identify the food in the image as accurately as possible.\n2. Estimate the nutritional values of the food, including: Carbohydrates (g), Sugars (g), Fats (g), Proteins (g), Calories (kcal),sodium， fibre, and any other nutrients(like vitamin...).\n3. Give a strict health rating for a type 2 diabetes patient: 「非常健康」, 「良好」, 「安全」, 「適量」, 「略為不健康」, 「風險高」, 「極度不建議」.\n4. Explain your reasoning clearly: Pros and cons of this food for someone with type 2 diabetes and without a gallbladder.\n5. Compare sugar/carbs to daily recommended limits For a person with type 2 diabetes, and for a healthy person.\n6. Compare calorie/fat to daily recommendations.\n7. Recommend healthier alternatives with various variety and provide personalized advice.\n7.5: Cheer me up.\n8.Finally, under the current context, suggest 7 further questions that I can ask you to get deeper insights.\n\nFormat the detailed analysis in Chinese Traditional and Markdown.\n\nCRITICAL FINAL INSTRUCTION:\nThe VERY FIRST LINE of your response MUST be strictly in this format (No Markdown, No Introduction):\nSUMMARY: [Food Name] | [Calories]千卡 | [Carbs]克碳水 | [Rating]\nExample: SUMMARY: 海南雞飯 | 600千卡 | 50克碳水 | 略為不健康\nDO NOT output anything before this line.";
      
      String fullText = "";
      try {
        await for (final chunk in _geminiService.chatFoodStream(prompt, [], image: image)) {
            fullText += chunk;
            entry.chatHistory.last = "model:$fullText";
            
            // Try to extract summary on the fly if it appears early
            // Only strictly needed at end, but nice to have.
            // Let's just update full text.
            notifyListeners();
        }
        
        // Finalize
        entry.fullResponse = fullText;
        
        // Extract summary
        // Same logic as _extractVerdict
        final RegExp summaryRegex = RegExp(r'^(?:\\*\\*)?SUMMARY(?:\\*\\*)?:\\s*(.+)$', caseSensitive: false, multiLine: true);
        final match = summaryRegex.firstMatch(fullText);
        
        if (match != null) {
          entry.summary = match.group(0)!; // Keep full SUMMARY line for now or parse parts? 
          // The current app logic expects entry.summary to be just the data? 
          // Wait, the previous logic parsed entry.summary for UI display?
          // No, existing entries have entire JSON or String.
          
          // Let's parse the parts to update entry fields
          final summaryLine = match.group(1)!.trim(); // "Name | Cals | Carbs | Rating"
          entry.summary = "SUMMARY: $summaryLine"; // Store standardized format
        } else {
             // Fallback
             entry.summary = "分析完成";
        }
        
        await entry.save();
        notifyListeners();

      } catch (e) {
          entry.chatHistory.last = "model:分析失敗: $e";
          entry.summary = "Error";
          await entry.save();
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

  Future<FoodEntry> startFreeChat() async {
    final entry = FoodEntry(
      id: DateTime.now().toIso8601String(),
      imagePath: "FREE_CHAT", // Marker for Free Chat
      fullResponse: "歡迎！這是您的自由聊天空間。您可以隨意發問。",
      summary: "自由聊天",
      timestamp: DateTime.now(),
      chatHistory: [],
    );
    await _box.add(entry);
    notifyListeners();
    return entry;
  }

  Future<void> sendChatMessage(FoodEntry entry, String message) async {
    _isLoading = true;
    notifyListeners();
    
    // Optimistic Update: Add user message immediately
    entry.chatHistory.add("user:$message");
    await entry.save(); // Save to Hive
    notifyListeners();

    try {
        // Pass history EXCLUDING the just-added message
        final historyToSend = entry.chatHistory.take(entry.chatHistory.length - 1).toList();
        
        File? imageFile;
        if (entry.imagePath.isNotEmpty && entry.imagePath != "MEAL_PLAN" && entry.imagePath != "HEALTH_QUERY" && entry.imagePath != "FREE_CHAT") {
           imageFile = File(entry.imagePath);
        }

        // Free Chat suffix logic
        String messageToSend = message;
        if (entry.imagePath == "FREE_CHAT") {
             messageToSend += " \n\nAt the End, Under the current context, suggest 7 further questions that I can ask you to get further or deeper insights. Remember all output should be written in Chinese Traditinoal";
        }

        // STREAMING IMPLEMENTATION
        // 1. Add placeholder for AI response
        entry.chatHistory.add("model:"); 
        notifyListeners();
        
        String fullResponse = "";

        // 2. Listen to stream
        await for (final chunk in _geminiService.chatFoodStream(messageToSend, historyToSend, image: imageFile)) {
           fullResponse += chunk;
           // Update the last message (which is the model response)
           entry.chatHistory.last = "model:$fullResponse";
           notifyListeners();
        }

        // 3. Save final state
        await entry.save();

    } catch (e) {
        entry.chatHistory.add("model:錯誤: 無法連接 AI ($e)");
        await entry.save();
    } finally {
        _isLoading = false;
        notifyListeners();
    }
  }



  // NEW: Helper to extract the structured summary line if available
  String _extractVerdict(String response) {
    // 1. Check for Structured Summary first
    // Format: SUMMARY: [Name] | [Calories] | [Carbs] | [Rating]
    // Regex allows:
    // - Case insensitive "summary"
    // - Optional ** bold markers
    // - Optional whitespace
    final RegExp summaryRegex = RegExp(r'^(?:\*\*)?SUMMARY(?:\*\*)?:\s*(.+)$', caseSensitive: false, multiLine: true);
    final match = summaryRegex.firstMatch(response);
    
    if (match != null) {
      return match.group(1)!.trim(); // Returns "Name | Cals | Carbs | Rating"
    }

    // 2. Fallback to extracting just the rating (Legacy behavior)
    return _extractLegacyRating(response);
  }

  String _extractLegacyRating(String response) {
     if (response.contains("非常健康")) return "非常健康";
    if (response.contains("良好")) return "良好";
    if (response.contains("安全")) return "安全";
    if (response.contains("適量")) return "適量";
    if (response.contains("略為不健康")) return "略為不健康";
    if (response.contains("風險高")) return "風險高";
    if (response.contains("極度不建議")) return "極度不建議";
    if (response.contains("Safe")) return "Safe";
    if (response.contains("Moderate")) return "Moderate";
    if (response.contains("Risky")) return "Risky";
    return "未知";
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime? _selectedMonth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('糖友紀錄'),
        centerTitle: true,
        actions: [
          Consumer<FoodProvider>(
            builder: (context, provider, child) {
              // Get available months from entries
              final months = provider.entries
                  .map((e) => DateTime(e.timestamp.year, e.timestamp.month))
                  .toSet()
                  .toList()
                  ..sort((a, b) => b.compareTo(a)); // Newest first

              return PopupMenuButton<DateTime?>(
                icon: const Icon(Icons.filter_list),
                tooltip: "依月份篩選",
                onSelected: (date) {
                  setState(() {
                    _selectedMonth = date;
                  });
                },
                itemBuilder: (context) {
                  return [
                    const PopupMenuItem<DateTime?>(
                      value: null,
                      child: Text("全部顯示"),
                    ),
                    ...months.map((date) {
                      return PopupMenuItem<DateTime?>(
                        value: date,
                        child: Text(DateFormat('yyyy年 MM月', 'zh_HK').format(date)),
                      );
                    }),
                  ];
                },
              );
            },
          ),
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
          // Filter entries
          final filteredEntries = _selectedMonth == null
              ? provider.entries
              : provider.entries.where((e) {
                  return e.timestamp.year == _selectedMonth!.year &&
                         e.timestamp.month == _selectedMonth!.month;
                }).toList();

          if (filteredEntries.isEmpty) {
             if (provider.entries.isEmpty) {
               return const Center(child: Text('暫無紀錄，請掃描食物！'));
             } else {
               return Center(
                 child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     const Text('此月份沒有紀錄'),
                     TextButton(
                       onPressed: () => setState(() => _selectedMonth = null),
                       child: const Text("查看全部"),
                     )
                   ],
                 ),
               );
             }
          }
          return ListView.builder(
            itemCount: filteredEntries.length,
            itemBuilder: (context, index) {
              final entry = filteredEntries[index];
              
              // PARSE INFO
              String foodName = "未知食物";
              String cals = "";
              String carbs = "";
              String rating = "未知";
              
              final parts = entry.summary.split('|');
              if (parts.length >= 4) {
                 // New Format: Name | Cals | Carbs | Rating
                 foodName = parts[0].trim();
                 cals = parts[1].trim();
                 carbs = parts[2].trim();
                 rating = parts[3].trim();
              } else {
                 // Legacy Format: Just Rating or custom string
                 if (entry.imagePath == "MEAL_PLAN") {
                   foodName = "一日三餐建議";
                   rating = "建議";
                 } else if (entry.imagePath == "HEALTH_QUERY") {
                   foodName = "健康問診";
                   rating = "諮詢";
                 } else {
                   foodName = "食物紀錄"; // Default for old entries
                   rating = entry.summary;
                 }
              }

              // Special handling for non-food types to look consistent
              if (entry.imagePath == "MEAL_PLAN") {
                foodName = "一日三餐建議";
                cals = "";
                carbs = "";
                rating = ""; 
              } else if (entry.imagePath == "HEALTH_QUERY") {
                // Parsing detail from summary for Health Query if we stored formatted string, 
                // but usually legacy logic applies directly. 
                // Let's keep specific logic for visual cleanliness.
                rating = "健康分析";
                if (entry.summary.startsWith("健康諮詢:")) {
                   foodName = entry.summary.replaceAll("健康諮詢: ", "");
                }
              }


              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                child: InkWell(
                  onTap: () {
                     Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DetailScreen(entry: entry),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // IMAGE
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: entry.imagePath == "MEAL_PLAN" 
                            ? Container(
                                width: 70, height: 70,
                                color: Colors.teal.shade100,
                                child: const Icon(Icons.restaurant_menu, color: Colors.teal, size: 30),
                              )
                            : entry.imagePath == "HEALTH_QUERY"
                              ? Container(
                                  width: 70, height: 70,
                                  color: Colors.red.shade100,
                                  child: const Icon(Icons.medical_services, color: Colors.deepOrange, size: 30),
                                )
                              : entry.imagePath == "FREE_CHAT"
                                ? Container(
                                    width: 70, height: 70,
                                    color: Colors.blue.shade100,
                                    child: const Icon(Icons.chat_bubble_outline, color: Colors.blue, size: 30),
                                  )
                                : (entry.imagePath.isEmpty
                                ? Container(
                                    width: 70, height: 70,
                                    color: Colors.orange.shade100,
                                    child: const Icon(Icons.edit_note, color: Colors.orange, size: 30),
                                  )
                                : Image.file(
                                    File(entry.imagePath),
                                    width: 70,
                                    height: 70,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image),
                                  )),
                        ),
                        
                        const SizedBox(width: 12),
                        
                        // TEXT CONTENT
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Line 1: Date (Smaller, Light Grey)
                              // Format: MM月dd日... yyyy年
                              // Requested: 12月18日下午6時52分 2025年
                              Text(
                                "${DateFormat('MM月dd日a h時mm分', 'zh_HK').format(entry.timestamp).replaceAll('下午下午', '下午').replaceAll('上午上午', '上午')} ${DateFormat('yyyy年', 'zh_HK').format(entry.timestamp)}",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),

                              // Line 2: Rating + Name (Bold)
                              RichText(
                                text: TextSpan(
                                  style: DefaultTextStyle.of(context).style,
                                  children: [
                                    if (rating.isNotEmpty && entry.imagePath != "MEAL_PLAN" && entry.imagePath != "FREE_CHAT")
                                      TextSpan(
                                        text: "$rating ",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: _getVerdictColor(rating),
                                          fontSize: 16,
                                        ),
                                      ),
                                    TextSpan(
                                      text: foodName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        // Apply the same color to the Name as requested
                                        color: _getVerdictColor(rating) != Colors.grey ? _getVerdictColor(rating) : Colors.black87,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              
                              const SizedBox(height: 4),

                              // Line 3: Details (Calories | Carbs)
                              if (cals.isNotEmpty || carbs.isNotEmpty)
                                Text(
                                  "$cals | $carbs",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              else if (entry.imagePath != "MEAL_PLAN" && entry.imagePath != "HEALTH_QUERY" && entry.imagePath != "FREE_CHAT")
                                // Placeholder for formatting consistency if data missing
                                const SizedBox.shrink(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
            heroTag: "free_chat_btn",
            onPressed: () async {
               final provider = Provider.of<FoodProvider>(context, listen: false);
               final entry = await provider.startFreeChat();
               if (context.mounted) {
                 Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DetailScreen(entry: entry)),
                );
               }
            },
            label: const Text('自由聊天'),
            icon: const Icon(Icons.chat_bubble),
            backgroundColor: Colors.blue.shade100,
            foregroundColor: Colors.blue.shade900,
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
          _startImageAnalysisStream(context, File(pickedFile.path));
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

  void _startImageAnalysisStream(BuildContext context, File image) async {
      // 1. Create entry & Start stream
      final provider = Provider.of<FoodProvider>(context, listen: false);
      final entry = await provider.analyzeFoodStreamed(image);
      
      if (!context.mounted) return;

      // 2. Navigate immediately to DetailScreen
      Navigator.push(
       context,
       MaterialPageRoute(
          builder: (_) => DetailScreen(entry: entry),
       ),
      );
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
          : widget.entry.imagePath == "FREE_CHAT"
            ? Container(
                width: double.infinity,
                height: 150,
                color: Colors.blue.shade50,
                child: const Center(child: Icon(Icons.chat_bubble_outline, size: 80, color: Colors.blue)),
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
          if (widget.entry.imagePath == "FREE_CHAT")
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  label: const Text('我可以問什麼?'),
                  avatar: const Icon(Icons.help_outline, size: 16),
                  backgroundColor: Colors.blue.shade50,
                  onPressed: () {
                      final prompt = """I am a 60-year-old man living in Hong Kong with type 2 diabetes. I want to live a good, fulfilling life in all aspects—physical health, mental well-being, relationships, and purpose.
From your perspective as an AI, what are the most important and insightful questions I should ask you to help guide me toward that goal?
Please analyze and answer in detail ,remember to answer in Traditional Chinese with Markdown formatting, considering various dimensions such as:
– Health and disease management
– Lifestyle and habits
– Emotional and mental well-being
– Social life and relationships
– Purpose, meaning, and personal growth
– Cultural and regional context (specific to Hong Kong)
""";
                      provider.sendChatMessage(widget.entry, prompt);
                  },
                ),
              ),
            ),
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
    // MASK THE LONG PROMPT IN UI
    if (isUser && text.contains("I am a 60-year-old man living in Hong Kong with type 2 diabetes. I want to live a good")) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.teal.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text("思考中...", style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic)),
        ),
      );
    }

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
