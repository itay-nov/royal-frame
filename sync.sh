
#!/bin/bash

echo "--- Starting Git Sync ---"

# 1. בדיקה שאנחנו ב-aiplayground
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "ai-playground" ]; then
  echo "Error: You are on '$CURRENT_BRANCH', please switch to 'ai-playground' first."
  exit 1
fi

# 2. שמירה (Commit) של כל השינויים הנוכחיים
echo "Saving local changes..."
git add .
if ! git commit -m "Auto-sync: Saving progress before merge"; then
    echo "No changes to commit, continuing..."
fi

# 3. מעבר למאסטר ומיזוג
echo "Switching to master and merging..."
git checkout master
git pull origin master
git merge ai-playground

# 4. דחיפה לשרת
echo "Pushing to remote..."
if git push origin master; then
    echo "SUCCESS: Everything is up to date on master!"
else
    echo "ERROR: Failed to push to master. Please check for conflicts."
    exit 1
fi

# 5. חזרה לעבודה
git checkout ai-playground
echo "--- Sync Complete! You are back on ai-playground ---"