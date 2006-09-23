use strict;
use Test::More;
use File::Spec::Functions qw(catfile);
use File::Basename qw(basename);
use Smolder::Conf qw(InstallRoot HostName ApachePort);
use Smolder::DB::SmokeReport;
use Smolder::DB::ProjectDeveloper;
use Smolder::TestData qw(
  create_project
  delete_projects
  create_developer
  delete_developers
  create_preference
  delete_preferences
);

plan(tests => 34);

my $bin          = catfile( InstallRoot(), 'bin', 'smolder_smoke_signal' );
my $host         = HostName() . ':' . ApachePort();
my $project      = create_project();
my $project_name = $project->name;
my $pw           = 's3cr3t';
my $dev          = create_developer( password => $pw );
my $username     = $dev->username;
my $xml_file     = catfile( InstallRoot(), 't', 'data', 'report_good.xml' );
my $xml_file_gz  = catfile( InstallRoot(), 't', 'data', 'report_good.xml.gz' );
my $yaml_file    = catfile( InstallRoot(), 't', 'data', 'report_good.yaml' );

END {
    delete_projects();
    delete_developers();
    delete_preferences();
}

# test required options
my $out = `$bin 2>&1`;
like( $out, qr/Missing required field 'server'/i );
$out = `$bin --server $host 2>&1`;
like( $out, qr/Missing required field 'project'/i );
$out = `$bin --server $host --project $project_name 2>&1`;
like( $out, qr/Missing required field 'username'/i );
$out = `$bin --server $host --project $project_name --username $username 2>&1`;
like( $out, qr/Missing required field 'password'/i );
$out = `$bin --server $host --project $project_name --username $username --password $pw 2>&1`;
like( $out, qr/Missing required field 'file'/i );

# invalid file
$out =
`$bin --server $host --project $project_name --username $username --password $pw --file stuff 2>&1`;
like( $out, qr/does not exist/i );

# invalid server
$out =
`$bin --server something.tld --project $project_name --username $username --password $pw --file $xml_file 2>&1`;
like( $out, qr/Could not reach/i );

SKIP: {
    # non-existant project
    $out =
`$bin --server $host --project "${project_name}asdf" --username $username --password $pw --file $xml_file 2>&1`;
    skip( "Smolder not running", 14 )
      if ( $out =~ /Received status 500/ );
    like( $out, qr/you are not a member of/i );

    # invalid login
    $out =
`$bin --server $host --project "$project_name" --username $username --password asdf --file $xml_file 2>&1`;
    like( $out, qr/Could not login/i );

    # non-project-member
    $out =
`$bin --server $host --project "$project_name" --username $username --password $pw --file $xml_file 2>&1`;
    like( $out, qr/you are not a member of/i );

    # add this person to the project
    Smolder::DB::ProjectDeveloper->create(
        {
            project    => $project,
            developer  => $dev,
            preference => create_preference(),
        }
    );
    Smolder::DB->dbi_commit();
    Smolder::DB->db_Main->disconnect();

    # successfull xml upload
    $out =
`$bin --server $host --project "$project_name" --username $username --password $pw --file $xml_file 2>&1`;
    like( $out, qr/successfully uploaded/i, 'XML' );

    # make sure it's uploaded to the server
    $out =~ /as #(\d+)/;
    my $report_id = $1;
    my $report    = Smolder::DB::SmokeReport->retrieve($report_id);
    isa_ok( $report, 'Smolder::DB::SmokeReport' );
    Smolder::DB->db_Main->disconnect();

    # successfull xml gzip upload
    $out =
`$bin --server $host --project "$project_name" --username $username --password $pw --file $xml_file_gz 2>&1`;
    like( $out, qr/successfully uploaded/i, 'XML Gzip' );

    # make sure it's uploaded to the server
    $out =~ /as #(\d+)/;
    $report_id = $1;
    $report    = Smolder::DB::SmokeReport->retrieve($report_id);
    isa_ok( $report, 'Smolder::DB::SmokeReport' );
    ok( $report->html, 'html can be created' );
    ok( $report->yaml, 'yaml can be created' );
    Smolder::DB->db_Main->disconnect();

    # successfull yaml gzip upload
    $out =
`$bin --server $host --project "$project_name" --username $username --password $pw --file $yaml_file 2>&1`;
    like( $out, qr/successfully uploaded/i );

    # make sure it's uploaded to the server
    $out =~ /as #(\d+)/;
    $report_id = $1;
    $report    = Smolder::DB::SmokeReport->retrieve($report_id);
    isa_ok( $report, 'Smolder::DB::SmokeReport' );
    ok( $report->html, 'html can be created' );
    ok( $report->xml,  'xml can be created' );
    Smolder::DB->db_Main->disconnect();

    # test optional options
    # comments
    my $comments = "Some tests";
    $out =
`$bin --server $host --project "$project_name" --username $username --password $pw --file $xml_file --comments "$comments" 2>&1`;
    like( $out, qr/successfully uploaded/i );
    $out =~ /as #(\d+)/;
    $report_id = $1;
    $report    = Smolder::DB::SmokeReport->retrieve($report_id);
    is( $report->comments, $comments );
    Smolder::DB->db_Main->disconnect();

    # platform
    my $platform = "my platform";
    $out =
`$bin --server $host --project "$project_name" --username $username --password $pw --file $xml_file --comments "$comments" --platform "$platform" 2>&1`;
    like( $out, qr/successfully uploaded/i );
    $out =~ /as #(\d+)/;
    $report_id = $1;
    $report    = Smolder::DB::SmokeReport->retrieve($report_id);
    is( $report->comments, $comments );
    is( $report->platform, $platform );
    Smolder::DB->db_Main->disconnect();

    # architecture
    my $arch = "128 bit something";
    $out =
`$bin --server $host --project "$project_name" --username $username --password $pw --file $xml_file --comments "$comments" --platform "$platform" --architecture "$arch" 2>&1`;
    like( $out, qr/successfully uploaded/i );
    $out =~ /as #(\d+)/;
    $report_id = $1;
    $report    = Smolder::DB::SmokeReport->retrieve($report_id);
    is( $report->comments,     $comments );
    is( $report->platform,     $platform );
    is( $report->architecture, $arch );
    Smolder::DB->db_Main->disconnect();

    # category
    my $cat = 'fake category';
    $project->add_category($cat);
    Smolder::DB->dbi_commit();
    Smolder::DB->db_Main->disconnect();
    $out =
`$bin --server $host --project "$project_name" --username $username --password $pw --file $xml_file --comments "$comments" --platform "$platform" --architecture "$arch" --category '$cat' 2>&1`;
    like( $out, qr/successfully uploaded/i );
    $out =~ /as #(\d+)/;
    $report_id = $1;
    $report    = Smolder::DB::SmokeReport->retrieve($report_id);
    is( $report->comments,     $comments );
    is( $report->platform,     $platform );
    is( $report->architecture, $arch );
    is( $report->category,     $cat );
    Smolder::DB->db_Main->disconnect();
}
