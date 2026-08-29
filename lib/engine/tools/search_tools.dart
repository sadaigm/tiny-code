import '../file_worker.dart';
import 'registry.dart';
import '../models.dart' show ToolDefinition;

/// grep + glob — executed on the file-worker isolate pool.
void registerSearchTools(ToolRegistry registry, FileWorkerPool pool) {
  registry
    ..register(grepDef(pool), _grep(pool))
    ..register(globDef(pool), _glob(pool));
}

ToolDefinition grepDef(FileWorkerPool pool) => ToolDefinition(
      name: 'grep',
      description: 'Search file contents under a directory. Plain substring '
          'by default, or regex with is_regex. Returns file:line: text matches.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'pattern': {'type': 'string'},
          'path': {
            'type': 'string',
            'description': 'Directory or file to search (default: cwd)',
          },
          'is_regex': {'type': 'boolean'},
        },
        'required': ['pattern'],
      },
    );

ToolHandler _grep(FileWorkerPool pool) => (args, ctx) async {
      final result = await pool.run({
        'op': 'grep',
        'root': args['path'] as String? ?? ctx.cwd,
        'pattern': args['pattern'] as String,
        'isRegex': args['is_regex'] as bool? ?? false,
      });
      final matches = (result['matches'] as List).cast<String>();
      if (matches.isEmpty) return 'No matches.';
      return '${matches.length} match(es):\n${matches.join('\n')}';
    };

ToolDefinition globDef(FileWorkerPool pool) => ToolDefinition(
      name: 'glob',
      description: 'List files matching a glob pattern (* and ?).',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'pattern': {'type': 'string', 'description': 'e.g. src/**/*.dart'},
        },
        'required': ['pattern'],
      },
    );

ToolHandler _glob(FileWorkerPool pool) => (args, ctx) async {
      final result = await pool.run({
        'op': 'glob',
        'root': ctx.cwd,
        'pattern': args['pattern'] as String,
      });
      final files = (result['files'] as List).cast<String>();
      if (files.isEmpty) return 'No files matched.';
      return files.join('\n');
    };
