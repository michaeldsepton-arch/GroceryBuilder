import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/recipe.dart';
import '../state/app_state.dart';
import '../theme.dart';

class RecipeImage extends StatelessWidget {
  const RecipeImage(this.recipe, {super.key, this.height = 140, this.radius = 18});
  final Recipe recipe;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      height: height,
      width: double.infinity,
      color: BB.green100,
      child: const Icon(Icons.restaurant_menu, color: BB.green500, size: 40),
    );
    Widget child = fallback;
    final img = recipe.image;
    if (recipe.photoPath != null && recipe.photoPath!.isNotEmpty) {
      final f = File(p.join(context.read<AppState>().photoDir, recipe.photoPath!));
      child = Image.file(f, height: height, width: double.infinity, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback);
    } else if (img != null && img.startsWith('asset:')) {
      child = Image.asset(img.substring(6), height: height, width: double.infinity, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback);
    } else if (img != null && img.isNotEmpty) {
      child = CachedNetworkImage(
          imageUrl: img, height: height, width: double.infinity, fit: BoxFit.cover,
          placeholder: (_, _) => fallback, errorWidget: (_, _, _) => fallback);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

class RecipeCard extends StatelessWidget {
  const RecipeCard(this.recipe, {super.key, required this.onTap, required this.favourite});
  final Recipe recipe;
  final VoidCallback onTap;
  final bool favourite;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              RecipeImage(recipe, height: 112, radius: 14),
              if (favourite)
                const Positioned(top: 6, right: 6, child: Icon(Icons.favorite, color: BB.tomato, size: 20)),
            ]),
            const SizedBox(height: 8),
            Text(recipe.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.15)),
            const SizedBox(height: 2),
            Text(
                [
                  if (recipe.cuisine.isNotEmpty) recipe.cuisine,
                  if (recipe.minutes != null) '${recipe.minutes} min',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: BB.muted, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
