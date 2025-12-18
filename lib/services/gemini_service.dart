import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class GeminiService {
  static const String apiKey = 'AIzaSyDLPXvUECpdft2aS1aYjp6joB1ZuqTBLN4';
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-preview:generateContent?key=$apiKey';

  Future<String> analyzeFood(File image) async {
    final bytes = await image.readAsBytes();
    final base64Image = base64Encode(bytes);

    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "contents": [
          {
            "parts": [
              {
                "text": "I am a 60 year old man live in Hong Kong, I have type 2 diabetes and have also had my gallbladder removed. You are an expert in nutrition for people with type 2 diabetes and post-cholecystectomy (gallbladder removal). I will upload an image of a food item or a food menu . Please: 1. Identify the food in the image as accurately as possible. 2. Estimate the nutritional values of the food, including: Carbohydrates (g), Sugars (g), Fats (g), Proteins (g), Calories (kcal),fibbre, and any other nutrients (e.g., vitamin, sodium, saturated fat). 3. Give a strict health rating for a type 2 diabetes patient, using one of these labels: 「非常健康」(Very Healthy), 「良好」(Good), 「安全」(Safe), 「適量」(Moderate), 「略為不健康」(Slightly Unhealthy), 「風險高」(Risky), 「極度不建議」(Too Risky). 4. Explain your reasoning clearly: Pros and cons of this food for someone with type 2 diabetes and without a gallbladder. 5. Compare this food’s sugar and carbohydrate content to daily recommended limits: For a person with type 2 diabetes, and for a healthy person. 6. Compare its calorie and fat content to daily intake recommendations. 7. Recommend healthier food alternatives with various variety, along with personalized health advice for someone with both conditions (type 2 diabetes + gallbladder removed).7.5: cheer me up by give me motivating and promising word 8. After that, under the current context, suggest 7 further questions that I can ask you to get deeper insights. Format the entire response in Chinese Traditional and Markdown."
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
      Uri.parse(_baseUrl),
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
  Future<String> analyzeText(String text) async {
    final prompt = "I am a 60 year old man live in Hong Kong, I have type 2 diabetes and have also had my gallbladder removed.My name is 張耀倫, you can call me 耀倫. You are an expert in nutrition for people with type 2 diabetes and post-cholecystectomy (gallbladder removal). I am asking about a food item: '$text'. Please: 1. Identify the food as accurately as possible. 2. Estimate the nutritional values of the food, including: Carbohydrates (g), Sugars (g), Fats (g), Proteins (g), Calories (kcal), fibre, and any other nutrients (e.g., vitamin, sodium, saturated fat). 3. Give a strict health rating for a type 2 diabetes patient, using one of these labels: 「非常健康」(Very Healthy), 「良好」(Good), 「安全」(Safe), 「適量」(Moderate), 「略為不健康」(Slightly Unhealthy), 「風險高」(Risky), 「極度不建議」(Too Risky). 4. Explain your reasoning clearly: Pros and cons of this food for someone with type 2 diabetes and without a gallbladder. 5. Compare this food’s sugar and carbohydrate content to daily recommended limits: For a person with type 2 diabetes, and for a healthy person. 6. Compare its calorie and fat content to daily intake recommendations. 7. Recommend healthier food alternatives with various variety, along with personalized health advice for someone with both conditions (type 2 diabetes + gallbladder removed). 7.5: cheer me up by give me motivating and promising word. 8. After that, under the current context, suggest 7 further questions that I can ask you to get deeper insights. Format the entire response in Chinese Traditional and Markdown.";

    final response = await http.post(
      Uri.parse(_baseUrl),
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
    const prompt = "I’m a 60-year-old man living in Hong Kong with type 2 diabetes and no gallbladder.My name is 張耀倫, you can call me 耀倫. You are a nutrition expert for diabetes and post-cholecystectomy patients. Please design a personalized one-day meal plan (3 meals), considering my condition and local diet preferences. Include: Recommended foods per meal (main, protein, veggies, fruit, fat source) Nutritional estimates Dietary principles explained Healthier versions of Hong Kong-style meals(both eat outside and cook at home) Timing tips and optional snacks Motivational words to support dietary discipline Answer in Traditional Chinese with Markdown formatting. also ,given my information and background (60-year-old man living in Hong Kong with type 2 diabetes), advice detaily from various perspective what i can do (activity i can do/event i can join/execerise i can do /entertainment/ personal developement / other ) ,both mental and physical, to have a better life and have a better health . at the end ,Based on this context, suggest 7 follow-up questions I can ask to explore deeper or more personalized insights.";

    final response = await http.post(
      Uri.parse(_baseUrl),
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
    final prompt = "You are a professional AI-powered health assistant and symptom analysis expert. You specialize in internal medicine, chronic diseases in older adults, and common medical conditions.Here is some of my background information (I am a 60 year old man live in Hong Kong, I have type 2 diabetes and have also had my gallbladder removed) .\nBased on the personal background, medical history, and symptoms I provide, perform the following tasks, : \n1.Analyze my current health situation and provide a list of possible conditions or diseases that may be related to my symptoms. \n2.Give professional Health advice base on my siutation, including: \n-What tests or examinations I should consider; \n-What kind of doctor or specialist I should consult; \n-Whether I should seek immediate medical attention. \n-Lifestyle or dietary adjustments I should make; \n-What i can do long term to improve my Health& Situation(excercise to do /supplement to take) \n3.Based on the current context, generate 5 intelligent follow-up questions that I can answer to help you understand more and 5 follow-up questions that i can ask ai further.\n 4.Please remember to answer me in Traditional Chinese. \nHere is my recent Situation/Symptoms : $symptoms";

    final response = await http.post(
      Uri.parse(_baseUrl),
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
