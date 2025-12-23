import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class GeminiService {
  // API Key is now handled on the server side for security
  // static const String apiKey = 'REMOVED'; 
  
  // Point to the user's personal Vercel Proxy Server
  // static const String _baseUrl = 'https://diabetes-friend.vercel.app/proxy_gemini'; // Old non-stream
  static const String _baseUrl = 'https://diabetes-friend.vercel.app';


  Future<String> analyzeFood(File image) async {
    final bytes = await image.readAsBytes();
    final base64Image = base64Encode(bytes);

    final response = await http.post(
      Uri.parse('$_baseUrl/proxy_gemini'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "contents": [
          {
            "parts": [
              {
                "text": "I am a 60 year old man live in Hong Kong, I have type 2 diabetes and also 膽囊有一顆3cm大小的膽結石和慢性膽囊炎.我有空喜歡過關跨境去深圳吃東西，也會留在香港吃。 My name is 張耀倫, you can call me 耀倫. You are an expert in nutrition for people with type 2 diabetes and 膽結石. I will upload an image of a food item or a food menu. \n\nPlease:\n1. Identify the food in the image as accurately as possible.\n2. Estimate the nutritional values of the food, including: Carbohydrates (g), Sugars (g), Fats (g), Proteins (g), Calories (kcal),sodium， fibre, and any other nutrients(like vitamin...).\n3. Give a health rating for a type 2 diabetes patient: 「非常健康」, 「良好」, 「安全」, 「適量」, 「略為不健康」, 「風險高」, 「極度不建議」.\n4. Explain your reasoning clearly: Pros and cons of this food for someone with type 2 diabetes and with 膽結石.\n5. Compare sugar/carbs to daily recommended limits For a person with type 2 diabetes, and for a healthy person.\n6. Compare calorie/fat to daily recommendations.\n7. Recommend healthier alternatives with various variety and provide personalized advice.\n7.5: Cheer me up.\n8.Finally, under the current context, suggest 7 further questions that I can ask you to get deeper insights.\n\nFormat the detailed analysis in Chinese Traditional and Markdown.（do not use english as i do not know english）\n\nCRITICAL FINAL INSTRUCTION:\nThe VERY FIRST LINE of your response MUST be strictly in this format (No Markdown, No Introduction):\nSUMMARY: [Food Name] | [Calories]千卡 | [Carbs]克碳水 | [Rating]\nExample: SUMMARY: 海南雞飯 | 600千卡 | 50克碳水 | 略為不健康\nDO NOT output anything before this line."
              },
              {
                "inline_data": {
                  "mime_type": "image/jpeg",
                  "data": base64Image
                }
              }
            ]
          }
        ]
      }),
    );

    return _parseResponse(response);
  }
  Future<String> chatFood(String query, List<String> history, {File? image}) async {
    String? base64Image;
    if (image != null) {
      final bytes = await image.readAsBytes();
      base64Image = base64Encode(bytes);
    }

    // Construct history for API
    List<Map<String, dynamic>> contents = [];

    // 1. Initial Image Analysis Prompt (Implicit Context)
    // We don't send the full initial prompt again to save tokens/complexity, 
    // but we re-send the image so the model "sees" it for the chat.
    // Ideally, we'd use a stateful chat session, but for REST simplicity we'll just send image + history.
    
    // Add History
    for (var item in history) {
      if (item.startsWith("user:")) {
        contents.add({
          "role": "user",
          "parts": [{"text": item.substring(5)}]
        });
      } else if (item.startsWith("model:")) {
        contents.add({
          "role": "model",
          "parts": [{"text": item.substring(6)}]
        });
      }
    }

    // Add Current User Query
    final userParts = <Map<String, dynamic>>[
      {"text": query}
    ];

    if (base64Image != null) {
      userParts.add({
        "inline_data": {
          "mime_type": "image/jpeg",
          "data": base64Image
        }
      });
    }

    contents.add({
      "role": "user",
      "parts": userParts
    });

    final response = await http.post(
      Uri.parse('$_baseUrl/proxy_gemini'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "contents": contents,
        "generationConfig": {
          "temperature": 0.7,
          "topK": 40,
          "topP": 0.95,
          "maxOutputTokens": 8192,
        }
      }),
    );

    return _parseResponse(response);
  }

  Stream<String> chatFoodStream(String query, List<String> history, {File? image}) async* {
    String? base64Image;
    if (image != null) {
      final bytes = await image.readAsBytes();
      base64Image = base64Encode(bytes);
    }

    // Construct history for API (Same as chatFood)
    List<Map<String, dynamic>> contents = [];
    for (var item in history) {
      if (item.startsWith("user:")) {
        contents.add({
          "role": "user",
          "parts": [{"text": item.substring(5)}]
        });
      } else if (item.startsWith("model:")) {
        contents.add({
          "role": "model",
          "parts": [{"text": item.substring(6)}]
        });
      }
    }

    final userParts = <Map<String, dynamic>>[{"text": query}];
    if (base64Image != null) {
      userParts.add({
        "inline_data": {
          "mime_type": "image/jpeg",
          "data": base64Image
        }
      });
    }
    contents.add({
      "role": "user",
      "parts": userParts
    });

    final request = http.Request('POST', Uri.parse('$_baseUrl/proxy_gemini_stream'));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      "contents": contents,
      // "generationConfig": ... // Optional
    });

    try {
      final client = http.Client();
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Stream Failed: ${streamedResponse.statusCode}');
      }

      // Transform stream to lines
      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
          
        if (line.startsWith('data: ')) {
          final dataStr = line.substring(6); // Remove 'data: '
          try {
            final json = jsonDecode(dataStr);
            if (json['text'] != null) {
              yield json['text'];
            }
          } catch (e) {
            // Ignore parse errors or "Error:" messages for now, just log
            print("Stream Parse Error: $e");
          }
        }
      }
      client.close();
    } catch (e) {
       yield " [Connection Error: $e]";
    }
  }

  Future<String> analyzeText(String text) async {
    final prompt = "I am a 60 year old man live in Hong Kong, I have type 2 diabetes and also 膽囊有一顆3cm大小的膽結石和慢性膽囊炎.我有空喜歡過關跨境去深圳吃東西，也會留在香港吃。 My name is 張耀倫. You are an expert in nutrition. I am asking about a food item: '$text'. \n\nPlease:\n1. Identify the food.\n2. Estimate nutritional values (Carbs, Sugar, Fat, Protein, Calories).\n3. Give a health rating: 「非常健康」, 「良好」, 「安全」, 「適量」, 「略為不健康」, 「風險高」, 「極度不建議」.\n4. Explain reasoning (Pros/Cons).\n5. Compare to daily limits.\n6. Compare to daily intake.\n7. Recommend alternatives and advice.\n7.5: Cheer me up.\n8. Suggest 7 questions.\n\nFormat in Chinese Traditional and Markdown.（do not use english as i do not know english）\n\nCRITICAL FINAL INSTRUCTION:\nThe VERY FIRST LINE of your response MUST be strictly in this format (No Markdown, No Introduction):\nSUMMARY: [Food Name] | [Calories]千卡 | [Carbs]克碳水 | [Rating]\nExample: SUMMARY: 海南雞飯 | 600千卡 | 50克碳水 | 略為不健康\nDO NOT output anything before this line.";

    final response = await http.post(
      Uri.parse('$_baseUrl/proxy_gemini'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": prompt}
            ]
          }
        ],
        "generationConfig": {
          "maxOutputTokens": 8192,
        }
      }),
    );

    return _parseResponse(response);
  }

  Future<String> getMealPlan() async {
    const prompt = "I’m a 60-year-old man living in Hong Kong with type 2 diabetes and also 膽囊有一顆3cm大小的膽結石和慢性膽囊炎.我有空喜歡過關跨境去深圳吃東西，也會留在香港吃。My name is 張耀倫, you can call me 耀倫. You are a nutrition expert for diabetes and 膽結石和慢性膽囊炎. Please design a personalized 7-day meal plan (3 meals a day), considering my condition and local diet preferences. Include: Recommended foods per meal (main, protein, veggies, fruit, fat source) Nutritional estimates Dietary principles explained Healthier versions of Hong Kong-style meals(both eat outside and cook at home) Timing tips and optional snacks Motivational words to support dietary discipline Answer in Traditional Chinese with Markdown formatting.（do not use english as i do not know english） Also ,given my information and background (60-year-old man living in Hong Kong with type 2 diabetes and also 膽囊有一顆3cm大小的膽結石和慢性膽囊炎), advice detaily from various perspective what i can do (activity i can do/event i can join/execerise i can do /entertainment/ personal developement / other ) ,both mental and physical, to have a better life and have a better health . at the end ,Based on this context, suggest 7 follow-up questions I can ask to explore deeper or more personalized insights.";

    final response = await http.post(
      Uri.parse('$_baseUrl/proxy_gemini'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": prompt}
            ]
          }
        ],
        "generationConfig": {
          "maxOutputTokens": 8192,
        }
      }),
    );

    return _parseResponse(response);
  }

  Future<String> analyzeHealth(String symptoms) async {
    final prompt = "You are a professional AI-powered health assistant and symptom analysis expert. You specialize in internal medicine, chronic diseases in older adults, and common medical conditions.Here is some of my background information (I am a 60 year old man live in Hong Kong, I have type 2 diabetes and also 膽囊有一顆3cm大小的膽結石和慢性膽囊炎.我有空喜歡過關跨境去深圳吃東西，也會留在香港吃。) .\nBased on the personal background, medical history, and symptoms I provide, perform the following tasks, : \n1.Analyze my current health situation and provide a list of possible conditions or diseases that may be related to my symptoms. \n2.Give professional Health advice base on my siutation, including: \n-What tests or examinations I should consider; \n-What kind of doctor or specialist I should consult; \n-Whether I should seek immediate medical attention. \n-Lifestyle or dietary adjustments I should make; \n-What i can do long term to improve my Health& Situation(excercise to do /supplement to take) \n3.Based on the current context, generate 5 intelligent follow-up questions that I can answer to help you understand more and 5 follow-up questions that i can ask ai further.\n 4.Please remember to answer me in Traditional Chinese.（do not use english as i do not know english） \nHere is my recent Situation/Symptoms : $symptoms";

    final response = await http.post(
      Uri.parse('$_baseUrl/proxy_gemini'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": prompt}
            ]
          }
        ],
        "generationConfig": {
          "maxOutputTokens": 8192,
        }
      }),
    );

    return _parseResponse(response);
  }

  String _parseResponse(http.Response response) {
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['candidates'] != null && 
          (json['candidates'] as List).isNotEmpty && 
          json['candidates'][0]['content'] != null &&
          json['candidates'][0]['content']['parts'] != null &&
          (json['candidates'][0]['content']['parts'] as List).isNotEmpty) {
        return json['candidates'][0]['content']['parts'][0]['text'];
      } else {
        throw Exception('AI analysis failed: Invalid response format or blocked content.');
      }
    } else {
      throw Exception('Failed to communicate with AI: ${response.statusCode} ${response.body}');
    }
  }
}
