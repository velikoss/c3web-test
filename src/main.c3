module another;

import c3web;
import c3web::server;
import c3web::config;

// fn HttpResponse Cref.folder(Request* req) 
// @Route("/folder") @Folder(FolderConfig{.path = "./web", .recursive = true, .hidden=false}) {
//     return {};
// }

// fn HttpResponse Cref.index(Request* req) 
// @Route("/hi") @File("./web/index.html") {
//     return {};
// }

// fn HttpResponse Cref.hi(Request* req) @Route("/hi") {
//     HttpResponse res;
//     res.status = OK;
//     res.body = dstring::new("Hi!!!", allocator: req.allocator);
//     return res;
// }

fn int main(String[] args) {
    Config config = config::read_from_file();
    return server::start_server(config);
}