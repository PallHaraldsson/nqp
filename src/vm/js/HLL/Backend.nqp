# Backend class for compiling to JavaScript.
use QAST::Compiler;

# HACK work around for nqp namespace bug
class HLLBackend::JavaScript {
    method apply_transcodings($s, $transcode) {
        $s
    }
    
    method config() {
        nqp::hash()
    }
    
    method force_gc() {
        nqp::die("Cannot force GC on JVM backend yet");
    }
    
    method name() {
        'js'
    }

    method nqpevent($spec?) {
        # Doesn't do anything just yet
    }
    
    method run_profiled($what) {
        nqp::printfh(nqp::getstderr(),
            "Attach a profiler (e.g. JVisualVM) and press enter");
        nqp::readlinefh(nqp::getstdin());
        $what();
    }
    
    method run_traced($level, $what) {
        nqp::die("No tracing support");
    }
    
    method version_string() {
        "JS"
    }
    
    method stages() {
        'js node'
    }
    
    method is_precomp_stage($stage) {
        # Currently, everything is pre-comp since we're a cross-compiler.
        1
    }
    
    method is_textual_stage($stage) {
        $stage eq 'js';
    }
    
    
    method js($qast, *%adverbs) {
        my $backend := QAST::CompilerJS.new(nyi=>%adverbs<nyi> // 'ignore', cps=>%adverbs<cps> // 'on');


        if %adverbs<source-map> {
            $backend.emit_with_source_map($qast);
        } else {
            my $code := $backend.emit($qast);
            $code := self.beautify($code) if %adverbs<beautify>;
            $code;
        }
    }

    method beautify($code) {
        my $tmp_file := self.tmp_file();


        my $fh := nqp::open($tmp_file, 'w');
        nqp::printfh($fh, $code);
        nqp::closefh($fh);

        my $pipe   := nqp::syncpipe();
        my $status := nqp::shell("uglifyjs $tmp_file -b", nqp::cwd(), nqp::getenvhash(),
            nqp::null(), $pipe, nqp::null(),
            nqp::const::PIPE_INHERIT_IN + nqp::const::PIPE_CAPTURE_OUT + nqp::const::PIPE_INHERIT_ERR);
        my $beautified := nqp::readallfh($pipe);
        nqp::closefh($pipe);

        # TODO think about safety
        nqp::unlink($tmp_file);

        $beautified;
    }

    method tmp_file() {
        # TODO a better temporary file name
        'tmp-' ~ nqp::getpid() ~ '.js';
    }
    
    method node($js, *%adverbs) {
        # TODO source map support
        my $tmp_file := self.tmp_file;

        my $code := nqp::open($tmp_file, 'w');
        nqp::printfh($code, $js);
        nqp::closefh($code);


        

        sub (*@args) {
            my @cmd := ["node",$tmp_file];

            my $i := 1;
            while $i < nqp::elems(@args) {
                @cmd.push(@args[$i]);
                $i := $i + 1;
            }

            my $env := nqp::getenvhash();
            nqp::spawn(@cmd,nqp::cwd(),nqp::getenvhash(),
                nqp::null(), nqp::null(), nqp::null(),
                nqp::const::PIPE_INHERIT_IN + nqp::const::PIPE_INHERIT_OUT + nqp::const::PIPE_INHERIT_ERR);
        
            nqp::unlink($tmp_file); # TODO think about safety
        };
    }

    method node_module($js, *%adverbs) {
        my $module := %adverbs<output>;
        if nqp::stat($module, nqp::const::STAT_EXISTS) == 0 {
            nqp::mkdir($module, 0o777);
        }

        spew($module ~ "/main.js", $js);
        my $package_json := '{ "main": "main.js", "version": "0.0.0", "name": "'~ %adverbs<name> ~ '" }';
        spew($module ~ '/package.json', $package_json);
    }

    method compunit_mainline($output) {
        $output;
    }
    
    method is_compunit($cuish) {
        1;
    }
}

# Role specifying the default backend for this build.
role HLL::Backend::Default {
    method default_backend() { HLLBackend::JavaScript }
}
