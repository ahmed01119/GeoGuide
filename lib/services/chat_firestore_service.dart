import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatFirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User is not logged in');
    }
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _sessionsRef {
    return _firestore.collection('users').doc(_uid).collection('chat_sessions');
  }

  Future<String> getOrCreateLatestSession() async {
    final snapshot = await _sessionsRef
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      return snapshot.docs.first.id;
    }

    return createNewSession();
  }

  Future<String> createNewSession() async {
    final doc = await _sessionsRef.add({
      'title': 'New Chat',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await addMessage(
      sessionId: doc.id,
      sender: 'bot',
      text:
          'Ahlan wa sahlan! Welcome! 🌙\n\nI’m your GeoGuide Egypt travel assistant.\nAsk me about destinations, food, hotels, and travel tips across Egypt.',
    );

    return doc.id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String sessionId) {
    return _sessionsRef
        .doc(sessionId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots();
  }

  Future<void> addMessage({
    required String sessionId,
    required String sender,
    required String text,
  }) async {
    await _sessionsRef.doc(sessionId).collection('messages').add({
      'sender': sender,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _sessionsRef.doc(sessionId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}