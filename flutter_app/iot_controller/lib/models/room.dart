import 'package:flutter/material.dart';

class Room {
  final String name;
  final IconData icon;
  final Color color;

  const Room({required this.name, required this.icon, required this.color});
}

const List<Room> defaultRooms = [
  Room(name: 'Phòng khách', icon: Icons.weekend, color: Colors.blue),
  Room(name: 'Phòng ngủ', icon: Icons.bed, color: Colors.indigo),
  Room(name: 'Bếp', icon: Icons.kitchen, color: Colors.orange),
  Room(name: 'Phòng tắm', icon: Icons.bathtub, color: Colors.teal),
  Room(name: 'Sân vườn', icon: Icons.yard, color: Colors.green),
  Room(name: 'Garage', icon: Icons.garage, color: Colors.brown),
  Room(name: 'Phòng làm việc', icon: Icons.computer, color: Colors.purple),
  Room(name: 'Unassigned', icon: Icons.devices_other, color: Colors.grey),
];

Room getRoomByName(String name) {
  return defaultRooms.firstWhere(
    (r) => r.name == name,
    orElse: () => defaultRooms.last,
  );
}
