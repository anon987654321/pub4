TTY::Tree.new('/my/project', level: 2, file_limit: 10,
              show_hidden: true, only_dirs: false, indent: 2).render
