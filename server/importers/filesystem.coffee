path = require 'path'
fs = require 'fs'

_ = require 'lodash'
Promise = require 'bluebird'
Promise.longStackSupport = true

easyimg = require 'easyimage'

{getAlbum, saveAlbum} = require '../server/db'
{makeBreadcrumb, slugify, sanitizeFilename, removeExtension} = require '../shared/helpers/path_helper'
{setThumbnail} = require '../shared/helpers/media_helper'
{Semaphore} = require '../shared/helpers/concurrency_helper'

readDirectory = Promise.promisify fs.readdir, fs
getImageInfo = Promise.promisify easyimg.info, easyimg

# TODO get the real prefix somewhere
stripPrefix = (fullPath, prefix) ->
  console.log fullPath, prefix
  throw 'Path is outside document root' if fullPath.indexOf(prefix) != 0
  fullPath[prefix.length..]

sem = new Semaphore 4

filesystemImport = (opts) ->
  {title, parent: parentPath, description, directory, root, concurrency} = opts

  root = path.resolve root
  sem = new Semaphore concurrency

  Promise.all([
    getAlbum(parentPath)
    readDirectory(path.resolve(root, directory))
  ]).spread (parent, files) ->
    Promise.all(files.map((basename) ->
      fullPath = path.resolve root, directory, basename
      sem.push -> getImageInfo(fullPath).then (imageInfo) ->
        process.stdout.write '.'
        imageInfo
    )).then (imageInfos) ->
      albumPath = path.join(parent.path, slugify(title))

      album =
        path: albumPath
        title: title
        description: description
        breadcrumb: makeBreadcrumb(parent)
        subalbums: []
        pictures: imageInfos.map (imageInfo) ->
          {name, width, height} = imageInfo[0]

          path: path.join(albumPath, sanitizeFilename(name))
          title: removeExtension(name)
          media: [
            {
              src: path.join('/', directory, name)
              width: parseInt width
              height: parseInt height
              original: true
            }
          ]

      setThumbnail album
      parent.subalbums.push _.pick album, 'path', 'title', 'thumbnail'
      setThumbnail parent

      # not saved in parallel to prevent zombie album ending up in parent if saving album fails
      saveAlbum(album)
    .then ->
      saveAlbum(parent)

if require.main is module
  argv = require('optimist')
    .usage('Usage: $0 --title "Album title" --parent / [directory]')
    .options('title', alias: 't', demand: true, describe: 'Album title')
    .options('description', alias: 'd', default: '', describe: 'Album description')
    .options('parent', alias: 'p', demand: true, describe: 'Path of the parent album')
    .options('directory', alias: 'i', demand: true, describe: 'Directory to import (relative to --root)')
    .options('root', alias: 'r', default: 'public', describe: 'Document root')
    .options('concurrency', alias: 'j', default: 4, describe: 'How many identify(1)s to run in parallel')
    .argv

  filesystemImport(argv).then ->
    process.exit()