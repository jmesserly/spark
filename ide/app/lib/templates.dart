// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library spark.templates;

import 'dart:async';
import 'dart:convert' show JSON;
import 'dart:html' hide File;

import 'package:chrome/chrome_app.dart' as chrome;

import 'utils.dart';
import 'workspace.dart';

/**
 * Specifies a variable-to-value substitution in a template file text.
 */
class TemplateVar {
  final String name;
  final String value;

  TemplateVar(this.name, this.value);

  String interpolate(String text) => text.replaceAll('``$name``', value);
}

/**
 * A class to create a sample project given a project name and a list of
 * template IDs to use as building blocks.
 *
 * Directories corresponding to the template IDs will be copied on top of
 * one another in random order; conflicts will not be detected nor resolved.
 */
class ProjectBuilder {
  DirectoryEntry _destRoot;
  List<ProjectTemplate> _templates = [];

  ProjectBuilder(this._destRoot, this._templates);

  /**
   * Build the sample project and complete the Future when finished.
   */
  Future build() {
    return Future.forEach(_templates, (ProjectTemplate template) {
      return template.build(_destRoot);
    });
  }

  /**
   * Return the 'main' file for the given project. This is generally the first
   * file we should show to the user after a project is created.
   */
  static Resource getMainResourceFor(Project project) {
    Resource r;

    r = project.getChild('manifest.json');
    if (r != null) return r;

    final Folder web = project.getChild('web');
    if (web != null) {
      r = web.getChildren().firstWhere(
          (r) => r.name.endsWith('.dart'), orElse: null);
      if (r != null) return r;

      r = web.getChildren().firstWhere(
          (r) => r.name.endsWith('.html'), orElse: null);
      if (r != null) return r;
    }

    return project;
  }
}

/**
 * A project template that knows how to instantiate itself within a given
 * destination directory.
 *
 * Instantiation consists of copying over files and directories listed in
 * the template's setup.json, with renaming the targets as specified.
 *
 * In addition, each source file's contents is pre-interpolated using the
 * provided global and local template variables.
 */
class ProjectTemplate {
  String _id;
  String _sourceUri;
  List<TemplateVar> _vars = [];

  ProjectTemplate(this._id,
                  [Map<String, String> globalVars,
                   Map<String, String> localVars]) {
    _sourceUri = 'resources/templates/$_id';
    for (var vars in [globalVars, localVars]) {
      if (vars != null) {
        vars.forEach((name, value) => _vars.add(new TemplateVar(name, value)));
      }
    }
  }

  Future build(DirectoryEntry destRoot) {
    DirectoryEntry sourceRoot;

    return getPackageDirectoryEntry().then((root) {
      return root.getDirectory(_sourceUri);
    }).then((dir) {
      sourceRoot = dir;
      return getAppContents("$_sourceUri/setup.json");
    }).then((String contents) {
      contents = _interpolateTemplateVars(contents);
      final Map m = JSON.decode(contents);
      return _traverseElement(destRoot, sourceRoot, _sourceUri, m);
    });
  }

  String _interpolateTemplateVars(String text) {
    return _vars.fold(text, (String t, TemplateVar v) => v.interpolate(t));
  }

  Future _traverseElement(DirectoryEntry destRoot, DirectoryEntry sourceRoot,
                          String sourceUri, Map element) {
    return _handleDirectories(destRoot, sourceRoot, sourceUri,
        element['directories']).then((_) =>
            _handleFiles(destRoot, sourceRoot, sourceUri, element['files']));
  }

  Future _handleDirectories(DirectoryEntry destRoot, DirectoryEntry sourceRoot,
                            String sourceUri, Map directories) {
    if (directories != null) {
      return Future.forEach(directories.keys, (String directoryName) {
        DirectoryEntry destDirectoryRoot;
        return destRoot.createDirectory(directoryName).then((DirectoryEntry entry) {
          destDirectoryRoot = entry;
          return sourceRoot.getDirectory(directoryName);
        }).then((DirectoryEntry sourceDirectoryRoot) {
          return _traverseElement(destDirectoryRoot, sourceDirectoryRoot,
              "$sourceUri/$directoryName", directories[directoryName]);
        });
      });
    }

    return new Future.value();
  }

  Future _handleFiles(DirectoryEntry destRoot, DirectoryEntry sourceRoot,
                      String sourceUri, List files) {
    if (files == null) return new Future.value();

    return Future.forEach(files, (fileElement) {
      String source = fileElement['source'];
      String dest = _interpolateTemplateVars(fileElement['dest']);
      chrome.ChromeFileEntry fileEntry;

      return destRoot.createFile(dest).then((chrome.ChromeFileEntry entry) {
        fileEntry = entry;
        if (dest.endsWith(".png")) {
          return getAppContentsBinary("$sourceUri/$source").then((List<int> data) {
            return fileEntry.writeBytes(new chrome.ArrayBuffer.fromBytes(data));
          });
        } else {
          return getAppContents("$sourceUri/$source").then((String data) {
            return fileEntry.writeText(_interpolateTemplateVars(data));
          });
        }
      });
    });
  }
}
