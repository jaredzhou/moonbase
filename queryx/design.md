```json
{
  "filter": {
    "id": 1,

    "age": {
      "gt": 18,
      "lt": 30
    },

    "name": {
      "contains": "tom"
    },

    "created_at": {
      "between": [
        "2024-01-01",
        "2025-01-01"
      ]
    },

    "or": [
      {
        "status": "A"
      },
      {
        "status": "B"
      }
    ]
  },

  "order_by": [
    {
      "age": "desc"
    },
    {
      "name": "asc"
    }
  ],

  "page": {
    "after":"asdfasfdasdfasdfasdf",
    "size": 10
  },
  
  "set": {
    "a": 1,
    "b": "haha"
  }
}
```