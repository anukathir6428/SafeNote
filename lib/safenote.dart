import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SafeNoteApp(),
    ),
  );
}

class SafeNoteApp extends StatefulWidget {
  const SafeNoteApp({super.key});

  @override
  State<SafeNoteApp> createState() => _SafeNoteAppState();
}

class _SafeNoteAppState extends State<SafeNoteApp> {

  int currentIndex = 0;

  final Telephony telephony = Telephony.instance;

  List<Map<String, dynamic>> notes = [];

  String emergencyName = "";
  String emergencyNumber = "";
  StreamSubscription<QuerySnapshot>? _notesSubscription;
  String searchQuery = "";
  String deviceId = "";

  @override
  void initState() {
    super.initState();

    initApp();
  }

  Future initApp() async {
    await loadEmergencyDetails();
    await setupDeviceAndNotes();
  }

  Future setupDeviceAndNotes() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString("device_id");
    if (id == null) {
      final random = Random();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomValue = random.nextInt(900000) + 100000;
      id = "dev_${timestamp}_$randomValue";
      await prefs.setString("device_id", id);
    }
    deviceId = id;
    listenToNotes();
  }

  void listenToNotes() {
    if (deviceId.isEmpty) return;

    _notesSubscription = FirebaseFirestore.instance
        .collection('devices')
        .doc(deviceId)
        .collection('notes')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          notes = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              "id": doc.id,
              "title": data["title"] ?? "",
              "content": data["content"] ?? "",
            };
          }).toList();
        });
      }
    });
  }

  @override
  void dispose() {
    _notesSubscription?.cancel();
    super.dispose();
  }

  // ================= SAVE EMERGENCY DETAILS =================

  Future saveEmergencyDetails(String name, String number) async {

    SharedPreferences prefs =
    await SharedPreferences.getInstance();

    await prefs.setString("emergency_name", name);
    await prefs.setString("emergency_number", number);

    setState(() {
      emergencyName = name;
      emergencyNumber = number;
    });
  }

  // ================= LOAD EMERGENCY DETAILS =================

  Future loadEmergencyDetails() async {

    SharedPreferences prefs =
    await SharedPreferences.getInstance();

    setState(() {
      emergencyName = prefs.getString("emergency_name") ?? "";
      emergencyNumber = prefs.getString("emergency_number") ?? "";
    });
  }

  // ================= GET LOCATION =================

  Future<String> getLocation() async {

  await Geolocator.requestPermission();

  Position position =
      await Geolocator.getCurrentPosition();

  return
      "https://maps.google.com/?q=${position.latitude},${position.longitude}";
}
  // ================= SEND SMS / SHARE =================

  Future sendEmergencySMS(String location) async {
    if (emergencyNumber.isEmpty) return;

    final message = "HELP! I need assistance. My current location is:\n$location";
    final cleanNumber = emergencyNumber.replaceAll(RegExp(r'[^\d+]'), '');

    // Try opening WhatsApp with pre-filled text
    final whatsappUrl = Uri.parse("https://wa.me/$cleanNumber?text=${Uri.encodeComponent(message)}");
    // Fallback SMS URL scheme
    final smsUrl = Uri.parse("sms:$cleanNumber?body=${Uri.encodeComponent(message)}");

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(smsUrl)) {
        await launchUrl(smsUrl);
      } else {
        // Web fallback (WhatsApp Web)
        final webUrl = Uri.parse("https://web.whatsapp.com/send?phone=$cleanNumber&text=${Uri.encodeComponent(message)}");
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint("Could not launch share action: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotes = notes.where((note) {
      final title = (note["title"] as String? ?? "").toLowerCase();
      final content = (note["content"] as String? ?? "").toLowerCase();
      return title.contains(searchQuery) || content.contains(searchQuery);
    }).toList();

    return Scaffold(

      backgroundColor: const Color(0xFF0F172A),

      // ================= APP BAR =================

      appBar: AppBar(

        backgroundColor: const Color(0xFF0F172A),

        elevation: 0,

        title: const Text(
          "SafeNote",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // ================= BODY =================

      body: Padding(

        padding: const EdgeInsets.all(15),

        child: Column(
          children: [

            // SEARCH BAR

            Container(

              padding:
              const EdgeInsets.symmetric(horizontal: 15),

              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(15),
              ),

              child: TextField(

                style: const TextStyle(color: Colors.white),

                onChanged: (value) {
                  setState(() {
                    searchQuery = value.toLowerCase();
                  });
                },

                decoration: const InputDecoration(
                  border: InputBorder.none,

                  hintText: "Search Notes...",

                  hintStyle:
                  TextStyle(color: Colors.white),

                  icon: Icon(
                    Icons.search,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ================= NOTES LIST =================

            Expanded(

              child: ListView.builder(

                itemCount: filteredNotes.length,

                itemBuilder: (context, index) {
                  final note = filteredNotes[index];

                  return GestureDetector(

                    // ================= EDIT NOTE =================

                    onTap: () async {

                      final updatedNote =
                      await Navigator.push(

                        context,

                        MaterialPageRoute(

                          builder: (context) => AddNotePage(

                            oldTitle:
                            note["title"],

                            oldContent:
                            note["content"],
                          ),
                        ),
                      );

                      if(updatedNote != null && note["id"] != null){
                        await FirebaseFirestore.instance
                            .collection('devices')
                            .doc(deviceId)
                            .collection('notes')
                            .doc(note["id"])
                            .update({
                          "title": updatedNote["title"] ?? "",
                          "content": updatedNote["content"] ?? "",
                          "timestamp": FieldValue.serverTimestamp(),
                        });
                      }
                    },

                    // ================= DELETE NOTE =================

                    onLongPress: () async {
                      if (note["id"] != null) {
                        await FirebaseFirestore.instance
                            .collection('devices')
                            .doc(deviceId)
                            .collection('notes')
                            .doc(note["id"])
                            .delete();

                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(

                            const SnackBar(
                              content: Text("Note Deleted"),
                            ),
                          );
                        }
                      }
                    },

                    child: Container(

                      margin:
                      const EdgeInsets.only(bottom: 15),

                      padding: const EdgeInsets.all(18),

                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius:
                        BorderRadius.circular(20),
                      ),

                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,

                        children: [

                          Text(

                            note["title"] ?? "",

                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),

                          const SizedBox(height: 10),

                          Text(

                            note["content"] ?? "",

                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),

      // ================= ADD NOTE BUTTON =================

      floatingActionButton: FloatingActionButton(

        backgroundColor: Colors.deepPurple,

        onPressed: () async {

          final newNote =
          await Navigator.push(

            context,

            MaterialPageRoute(
              builder: (context) =>
              const AddNotePage(),
            ),
          );

          if(newNote != null){

            String title = newNote["title"] ?? "";
            String content = newNote["content"] ?? "";
            String locationLink = "";

            // ================= ALERT WORD CHECK =================

            if(content.contains("HELP") ||
                content.contains("SOS") ||
                content.contains("DANGER")){

              String location =
              await getLocation();
              locationLink = location;

              // Append location link directly to content so it saves in DB and shows on screen
              content = "$content\n\nLocation:\n$location";

              await sendEmergencySMS(location);

              if (context.mounted) {
                showDialog(

                  context: context,

                  builder: (context){

                    return AlertDialog(

                      title:
                      const Text("Emergency Alert"),

                      content: const Text(
                        "Emergency SMS Sent!",
                      ),

                      actions: [

                        TextButton(

                          onPressed: () {

                            Navigator.pop(context);
                          },

                          child: const Text("OK"),
                        ),
                      ],
                    );
                  },
                );
              }
            }

            await FirebaseFirestore.instance
                .collection('devices')
                .doc(deviceId)
                .collection('notes')
                .add({
              "title": title,
              "content": content,
              "location": locationLink,
              "timestamp": FieldValue.serverTimestamp(),
            });
          }
        },

        child: const Icon(Icons.add),
      ),

      // ================= BOTTOM NAVIGATION =================

      bottomNavigationBar: BottomNavigationBar(

        currentIndex: currentIndex,

        backgroundColor: const Color(0xFF111827),

        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,

        onTap: (index){

          setState(() {
            currentIndex = index;
          });

          // ================= ALERT PAGE =================

          if(index == 1){

            Navigator.push(

              context,

              MaterialPageRoute(

                builder: (context) => AlertPage(

                  currentName: emergencyName,
                  currentNumber: emergencyNumber,

                  onSave: (name, number){

                    saveEmergencyDetails(name, number);
                  },
                ),
              ),
            );
          }

          // ================= SETTINGS PAGE =================

          if(index == 2){

            Navigator.push(

              context,

              MaterialPageRoute(
                builder: (context) =>
                const SettingsPage(),
              ),
            );
          }
        },

        items: const [

          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: "Home",
          ),

          BottomNavigationBarItem(
            icon: Icon(Icons.warning),
            label: "Alerts",
          ),

          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: "Settings",
          ),
        ],
      ),
    );
  }
}

// ================= ADD NOTE PAGE =================

class AddNotePage extends StatefulWidget {

  final String? oldTitle;
  final String? oldContent;

  const AddNotePage({

    super.key,

    this.oldTitle,
    this.oldContent,
  });

  @override
  State<AddNotePage> createState() =>
      _AddNotePageState();
}

class _AddNotePageState
extends State<AddNotePage> {

  TextEditingController titleController =
  TextEditingController();

  TextEditingController contentController =
  TextEditingController();

  @override
  void initState() {

    super.initState();

    titleController.text =
        widget.oldTitle ?? "";

    contentController.text =
        widget.oldContent ?? "";
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: const Color(0xFF0F172A),

      appBar: AppBar(

        backgroundColor:
        const Color(0xFF0F172A),

        title: const Text("Add Note"),
      ),

      body: Padding(

        padding: const EdgeInsets.all(20),

        child: Column(
          children: [

            // TITLE FIELD

            TextField(

              controller: titleController,

              style:
              const TextStyle(color: Colors.white),

              decoration: InputDecoration(

                hintText: "Title",

                hintStyle:
                const TextStyle(color: Colors.white54),

                filled: true,
                fillColor: Colors.white10,

                border: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(15),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // CONTENT FIELD

            TextField(

              controller: contentController,

              maxLines: 5,

              style:
              const TextStyle(color: Colors.white),

              decoration: InputDecoration(

                hintText: "Write your note...",

                hintStyle:
                const TextStyle(color: Colors.white54),

                filled: true,
                fillColor: Colors.white10,

                border: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(15),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // SAVE BUTTON

            SizedBox(

              width: double.infinity,
              height: 55,

              child: ElevatedButton(

                style:
                ElevatedButton.styleFrom(
                  backgroundColor:
                  Colors.deepPurple,
                ),

                onPressed: () {

                  Navigator.pop(

                    context,

                    {
                      "title":
                      titleController.text,

                      "content":
                      contentController.text,
                    },
                  );
                },

                child: const Text(
                  "Save Note",
                  style:
                  TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= ALERT PAGE =================

class AlertPage extends StatefulWidget {

  final String currentName;
  final String currentNumber;

  final Function(String, String)
  onSave;

  const AlertPage({

    super.key,

    required this.currentName,
    required this.currentNumber,

    required this.onSave,
  });

  @override
  State<AlertPage> createState() =>
      _AlertPageState();
}

class _AlertPageState
extends State<AlertPage> {

  late TextEditingController nameController;
  late TextEditingController numberController;

  @override
  void initState() {

    super.initState();

    nameController =
        TextEditingController(
          text: widget.currentName,
        );

    numberController =
        TextEditingController(
          text: widget.currentNumber,
        );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: const Color(0xFF0F172A),

      appBar: AppBar(

        backgroundColor:
        const Color(0xFF0F172A),

        title:
        const Text("Emergency Alert"),
      ),

      body: Padding(

        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,

          children: [

            const Text(

              "Emergency Contact Name",

              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            TextField(

              controller: nameController,

              style:
              const TextStyle(color: Colors.white),

              decoration: InputDecoration(

                hintText:
                "Enter Security Contact Name",

                hintStyle:
                const TextStyle(color: Colors.white54),

                prefixIcon: const Icon(
                  Icons.person,
                  color: Colors.white,
                ),

                filled: true,
                fillColor: Colors.white10,

                border: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(15),
                ),
              ),
            ),

            const SizedBox(height: 20),

            const Text(

              "Emergency Contact Number",

              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            TextField(

              controller: numberController,

              keyboardType:
              TextInputType.phone,

              style:
              const TextStyle(color: Colors.white),

              decoration: InputDecoration(

                hintText:
                "Enter Security Number",

                hintStyle:
                const TextStyle(color: Colors.white54),

                prefixIcon: const Icon(
                  Icons.phone,
                  color: Colors.white,
                ),

                filled: true,
                fillColor: Colors.white10,

                border: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(15),
                ),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(

              width: double.infinity,
              height: 55,

              child: ElevatedButton(

                style:
                ElevatedButton.styleFrom(
                  backgroundColor:
                  const Color.fromARGB(255, 136, 244, 191),
                ),

                onPressed: () {

                  widget.onSave(
                    nameController.text,
                    numberController.text,
                  );

                  ScaffoldMessenger.of(context)
                      .showSnackBar(

                    const SnackBar(
                      content: Text(
                        "Emergency Details Saved",
                      ),
                    ),
                  );
                },

                child: const Text(
                  "Save Details",
                  style:
                  TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= SETTINGS PAGE =================

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() =>
      _SettingsPageState();
}

class _SettingsPageState
extends State<SettingsPage> {

  TextEditingController nameController =
  TextEditingController();

  TextEditingController emailController =
  TextEditingController();

  TextEditingController phoneController =
  TextEditingController();

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future loadProfile() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      nameController.text = prefs.getString("profile_name") ?? "";
      emailController.text = prefs.getString("profile_email") ?? "";
      phoneController.text = prefs.getString("profile_phone") ?? "";
    });
  }

  Future saveProfile() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString("profile_name", nameController.text);
    await prefs.setString("profile_email", emailController.text);
    await prefs.setString("profile_phone", phoneController.text);
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: const Color(0xFF0F172A),

      appBar: AppBar(

        backgroundColor:
        const Color(0xFF0F172A),

        title: const Text("Settings"),
      ),

      body: SingleChildScrollView(

        padding: const EdgeInsets.all(20),

        child: Column(
          children: [

            const CircleAvatar(

              radius: 50,

              backgroundColor:
              Color.fromARGB(255, 103, 58, 180),

              child: Icon(
                Icons.person,
                size: 50,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 30),

            // NAME FIELD

            TextField(

              controller: nameController,

              style:
              const TextStyle(color: Colors.white),

              decoration: InputDecoration(

                hintText:
                "Enter Your Name",

                hintStyle:
                const TextStyle(color: Colors.white54),

                prefixIcon: const Icon(
                  Icons.person,
                  color: Colors.white,
                ),

                filled: true,
                fillColor: Colors.white10,

                border: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(15),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // EMAIL FIELD

            TextField(

              controller: emailController,

              style:
              const TextStyle(color: Colors.white),

              decoration: InputDecoration(

                hintText:
                "Enter Your Email",

                hintStyle:
                const TextStyle(color: Colors.white54),

                prefixIcon: const Icon(
                  Icons.email,
                  color: Colors.white,
                ),

                filled: true,
                fillColor: Colors.white10,

                border: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(15),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // PHONE FIELD

            TextField(

              controller: phoneController,

              keyboardType:
              TextInputType.phone,

              style:
              const TextStyle(color: Colors.white),

              decoration: InputDecoration(

                hintText:
                "Enter Phone Number",

                hintStyle:
                const TextStyle(color: Colors.white54),

                prefixIcon: const Icon(
                  Icons.phone,
                  color: Colors.white,
                ),

                filled: true,
                fillColor: Colors.white10,

                border: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(15),
                ),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(

              width: double.infinity,
              height: 55,

              child: ElevatedButton(

                style:
                ElevatedButton.styleFrom(
                  backgroundColor:
                  const Color.fromARGB(255, 136, 244, 191),
                ),

                onPressed: () async {
                  await saveProfile();

                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(

                      const SnackBar(
                        content: Text(
                          "Profile Saved Successfully",
                        ),
                      ),
                    );
                  }
                },

                child: const Text(
                  "Save Details",
                  style:
                  TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}