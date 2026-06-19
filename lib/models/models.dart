// ── Models ─────────────────────────────────────────────────────────────────

class BuddyUser {
  final String id;
  final String? fullName;
  final String? avatarUrl;
  final String? bio;
  final String? nationality;
  final String? docType;
  final String? docNumber;

  BuddyUser({required this.id, this.fullName, this.avatarUrl, this.bio, this.nationality, this.docType, this.docNumber});

  factory BuddyUser.fromJson(Map<String, dynamic> j) => BuddyUser(
    id: j['id'],
    fullName: j['full_name'],
    avatarUrl: j['avatar_url'],
    bio: j['bio'],
    nationality: j['nationality'],
    docType: j['doc_type'],
    docNumber: j['doc_number'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'avatar_url': avatarUrl,
    'bio': bio,
    'nationality': nationality,
    'doc_type': docType,
    'doc_number': docNumber,
  };
}

class HelpRequest {
  final String id;
  final String travelerId;
  final String destinationId;
  final String category;
  final String? description;
  final String status;
  final DateTime? arrivalAt;
  final DateTime createdAt;
  final BuddyUser? traveler;
  final Destination? destination;
  final int? secondsRemaining; // tiempo restante de la solicitud (matching escalonado)
  final String? outcome;       // historial: 'accepted' | 'missed' (null = activa)
  final DateTime? when;        // historial: cuándo se aceptó/perdió

  HelpRequest({
    required this.id,
    required this.travelerId,
    required this.destinationId,
    required this.category,
    this.description,
    required this.status,
    this.arrivalAt,
    required this.createdAt,
    this.traveler,
    this.destination,
    this.secondsRemaining,
    this.outcome,
    this.when,
  });

  factory HelpRequest.fromJson(Map<String, dynamic> j) => HelpRequest(
    id: j['id'],
    travelerId: j['traveler_id'],
    destinationId: j['destination_id'],
    category: j['category'] ?? 'general',
    description: j['description'],
    status: j['status'] ?? 'open',
    arrivalAt: j['arrival_at'] != null ? DateTime.tryParse(j['arrival_at']) : null,
    createdAt: j['created_at'] != null ? DateTime.parse(j['created_at']) : DateTime.now(),
    traveler: j['traveler'] != null ? BuddyUser.fromJson(j['traveler']) : null,
    destination: j['destination'] != null ? Destination.fromJson(j['destination']) : null,
    secondsRemaining: j['seconds_remaining'] as int?,
    outcome: j['outcome'],
    when: j['when'] != null ? DateTime.tryParse(j['when']) : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'traveler_id': travelerId,
    'destination_id': destinationId,
    'category': category,
    'description': description,
    'status': status,
    'arrival_at': arrivalAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'traveler': traveler?.toJson(),
    'destination': destination?.toJson(),
  };

  String get categoryLabel {
    const labels = {
      'transport': 'Transporte',
      'accommodation': 'Alojamiento',
      'food': 'Comida',
      'activities': 'Actividades',
      'emergency': 'Emergencia',
      'general': 'General',
    };
    return labels[category] ?? category;
  }
}

class Match {
  final String id;
  final String requestId;
  final String buddyId;
  final String travelerId;
  final String status;
  final DateTime createdAt;
  final HelpRequest? request;
  final BuddyUser? traveler;
  Message? lastMessage;

  Match({
    required this.id,
    required this.requestId,
    required this.buddyId,
    required this.travelerId,
    required this.status,
    required this.createdAt,
    this.request,
    this.traveler,
    this.lastMessage,
  });

  factory Match.fromJson(Map<String, dynamic> j) => Match(
    id: j['id'],
    requestId: j['request_id'],
    buddyId: j['buddy_id'],
    travelerId: j['traveler_id'],
    status: j['status'] ?? 'active',
    createdAt: DateTime.parse(j['created_at']),
    request: j['request'] != null ? HelpRequest.fromJson(j['request']) : null,
    traveler: j['traveler'] != null ? BuddyUser.fromJson(j['traveler']) : null,
  );
}

class Message {
  final String id;
  final String matchId;
  final String senderId;
  final String content;
  final String type;
  final String? audioUrl;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.matchId,
    required this.senderId,
    required this.content,
    required this.type,
    this.audioUrl,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> j) => Message(
    id:       j['id'],
    matchId:  j['match_id'],
    senderId: j['sender_id'],
    content:  j['content'] ?? '',
    type:     j['type'] ?? 'text',
    audioUrl: j['audio_url'],
    createdAt: DateTime.parse(j['created_at']),
  );
}

class Journey {
  final String id;
  final String? title;
  final String status;
  final DateTime? arrivalAt;
  final Destination? destination;

  Journey({required this.id, this.title, required this.status, this.arrivalAt, this.destination});

  factory Journey.fromJson(Map<String, dynamic> j) => Journey(
    id: j['id'],
    title: j['title'],
    status: j['status'] ?? 'planning',
    arrivalAt: j['arrival_at'] != null ? DateTime.tryParse(j['arrival_at']) : null,
    destination: j['destination'] != null ? Destination.fromJson(j['destination']) : null,
  );
}

class Destination {
  final String id;
  final String name;
  final String city;
  final String? coverUrl;

  Destination({required this.id, required this.name, required this.city, this.coverUrl});

  factory Destination.fromJson(Map<String, dynamic> j) => Destination(
    id: j['id'],
    name: j['name'],
    city: j['city'],
    coverUrl: j['cover_url'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'city': city,
    'cover_url': coverUrl,
  };
}
