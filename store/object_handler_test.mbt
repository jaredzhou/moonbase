// Tests for object REST handlers -- verifies route registration.

///|
test "object handler routes registered" {
  let storage = new_test_storage()
  let r = @pony.Router::Router()
  let _ = build_object_routes(r, storage)
  inspect(r, content=
    (
      #|Static()
      #|    └── Static(/object/)
      #|        ├── Static(authenticated/)
      #|        │   p── Param(bucketName,/)
      #|        │       └── Static(/)
      #|        │           w── * Get(/object/authenticated/{bucketName}/*)
      #|        ├── Static(public/)
      #|        │   p── Param(bucketName,/)
      #|        │       └── Static(/)
      #|        │           w── * Get(/object/public/{bucketName}/*)
      #|        ├── Static(info/)
      #|        │   ├── Static(public/)
      #|        │   │   p── Param(bucketName,/)
      #|        │   │       └── Static(/)
      #|        │   │           w── * Head(/object/info/public/{bucketName}/*) Get(/object/info/public/{bucketName}/*)
      #|        │   p── Param(bucketName,/)
      #|        │       └── Static(/)
      #|        │           w── * Head(/object/info/{bucketName}/*) Get(/object/info/{bucketName}/*)
      #|        ├── Static(list/)
      #|        │   p── Param(bucketName,/) Post(/object/list/{bucketName})
      #|        ├── Static(move) Post(/object/move)
      #|        ├── Static(copy) Post(/object/copy)
      #|        p── Param(bucketName,/) Delete(/object/{bucketName})
      #|            └── Static(/)
      #|                w── * Post(/object/{bucketName}/*) Get(/object/{bucketName}/*) Put(/object/{bucketName}/*) Delete(/object/{bucketName}/*)
      #|

)
  )
}
