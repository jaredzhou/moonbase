// LocalFS backend — stores files on the local filesystem.
// The StorageBackend trait impl is registered in the parent `moonstore` package.

///|
pub(all) struct LocalFSBackend {
  base_path : String
}

///|
/// Create a new LocalFS backend rooted at the given directory.
pub fn new(base_path : String) -> LocalFSBackend {
  LocalFSBackend::{ base_path }
}

///|
/// Build the full filesystem path for a (bucket_id, name) pair.
pub fn full_path(base_path : String, bucket_id : String, name : String) -> String {
  base_path + "/" + bucket_id + "/" + name
}

///|
/// Create a directory and all missing parent directories.
pub fn create_dir_all(path : String) -> Unit {
  if @fs.path_exists(path) {
    return
  }
  let dir_path : @path.Path = path
  let parent = @path.Path::dirname(dir_path).to_string()
  if parent != "" && parent != path {
    create_dir_all(parent)
  }
  @fs.create_dir(path) catch {
    _ => ()
  }
}

///|
/// Return the parent directory of the given path.
pub fn parent_dir(path : String) -> String {
  let p : @path.Path = path
  @path.Path::dirname(p).to_string()
}
