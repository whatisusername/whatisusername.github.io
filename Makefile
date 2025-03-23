.PHONY: local demo new_post

local:
	hugo server --buildDrafts --gc --minify --openBrowser

demo:
	hugo server --source themes/hugo-blog-awesome/exampleSite --gc --minify --openBrowser --themesDir ../.. --port 1314

new_post:
	hugo new content content/en/posts/$(NAME)/index.md
	hugo new content content/zh/posts/$(NAME)/index.md
