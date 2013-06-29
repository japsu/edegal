mysql = require 'mysql'
Q = require 'q'
_ = require 'underscore'
path = require 'path'
ent = require 'ent'

{albums, createIndexes, dropAlbums, getAlbum, saveAlbum} = require '../server/db'
{slugify, makeBreadcrumb} = require '../shared/helpers/path_helper'
{getThumbnail} = require '../shared/helpers/media_helper'

connection = mysql.createConnection
  host: 'localhost'
  port: 10000
  user: 'b2_coppermine'
  database: 'b2_coppermine'
  password: 'secret'
  insecureAuth: true

PLACEHOLDER_IMAGE = '/images/example_content_360x240.jpg'
CATEGORY_BLACKLIST = [
  1 # User galleries
  107 # Animeunioni
]

root =
  path: '/'
  title: 'Anikin kuva-arkisto'
  breadcrumb: []
  subalbums: []
  pictures: []

connection.connect()

query = Q.nbind connection.query, connection

getFirstLandscapePicture = (pictures) ->
  _.find pictures, (picture) ->
    anyMedia = _.first picture.media
    anyMedia.width >= anyMedia.height

setThumbnail = (album) ->
  album.thumbnail = do ->
    return album.thumbnail if album.thumbnail
    return pictureThumbnail if (picture = getFirstLandscapePicture album.pictures) and (pictureThumbnail = getThumbnail picture)
    return pictureThumbnail if (picture = _.first album.pictures) and (pictureThumbnail = getThumbnail picture)
    return subalbum.thumbnail if (subalbum = _.first album.subalbums) and subalbum.thumbnail
    PLACEHOLDER_IMAGE

convertCoppermine = ->
  Q.all([
    dropAlbums().fail(-> null)
    query("SET NAMES 'latin1';")
  ]).then ->
    convertSubcategories 0, root
  .then ->
    setThumbnail root
    saveAlbum root
  .then(createIndexes)

sanitizeFilename = (filename) ->
  [filename] = filename.split '.', 1
  slugify(filename)

decodeEntities = (obj, fields...) ->
  for field in fields
    obj[field] = ent.decode(obj[field] ? '')

convertSubcategories = (categoryId, parent) ->
  breadcrumb = makeBreadcrumb parent

  # get root category
  query('SELECT cid, name, description FROM cpg11d_categories WHERE parent = ? ORDER BY pos', [categoryId]).spread (categories) ->
    Q.all categories.map (coppermineCategory) ->
      return null if coppermineCategory.cid in CATEGORY_BLACKLIST

      decodeEntities coppermineCategory, 'name', 'description'
      slug = slugify(coppermineCategory.name) or "category-#{coppermineCategory.cid}"

      edegalAlbum =
        path: path.join(parent.path, slug)
        breadcrumb: breadcrumb
        title: coppermineCategory.name
        description: coppermineCategory.description
        subalbums: []
        pictures: []

      Q.all([
        convertSubcategories(coppermineCategory.cid, edegalAlbum),
        convertAlbums(coppermineCategory.cid, edegalAlbum)
      ]).then ->
        setThumbnail edegalAlbum
        parent.subalbums.push _.pick edegalAlbum, 'path', 'title', 'thumbnail'
        saveAlbum(edegalAlbum)

convertAlbums = (categoryId, parent) ->
  breadcrumb = makeBreadcrumb parent

  query('SELECT aid, title, description FROM cpg11d_albums WHERE category = ? ORDER BY pos', [categoryId]).spread (albums) ->
    Q.all albums.map (coppermineAlbum) ->
      decodeEntities coppermineAlbum, 'title', 'description'
      slug = slugify(coppermineAlbum.title) or "album-#{coppermineAlbum.aid}"

      edegalAlbum =
        path: path.join(parent.path, slug)
        breadcrumb: breadcrumb
        title: coppermineAlbum.title
        description: coppermineAlbum.description
        subalbums: []
        pictures: []

      convertPictures(coppermineAlbum.aid, edegalAlbum).then ->
        setThumbnail edegalAlbum
        parent.subalbums.push _.pick edegalAlbum, 'path', 'title', 'thumbnail'
        saveAlbum edegalAlbum

convertPictures = (albumId, parent) ->
  query('SELECT pid, filename, filepath, title, caption FROM cpg11d_pictures WHERE aid = ? ORDER BY position', [albumId]).spread (pictures) ->
    pictures.map (copperminePicture) ->
      decodeEntities copperminePicture, 'title', 'caption'
      title = copperminePicture.title or copperminePicture.filename
      parent.pictures.push
        path: path.join(parent.path, sanitizeFilename(copperminePicture.filename) or "picture-#{copperminePicture.pid}")
        title: title ? ''
        description: copperminePicture.caption ? ''
        media: [ 
          {
            src: "http://kuvat.aniki.fi/albums/#{copperminePicture.filepath}normal_#{copperminePicture.filename}",
            width: 600 # TODO
            height: 400 # TODO
          }
          {
            src: "http://kuvat.aniki.fi/albums/#{copperminePicture.filepath}#{copperminePicture.filename}",
            width: 6000 # TODO
            height: 4000 # TODO
            original: true
          }
        ]

if require.main is module
  convertCoppermine().then ->
    process.exit()
  .done()