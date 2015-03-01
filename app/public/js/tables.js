$(document).ready( function () {
    $('.ms_dataTable').DataTable({
        stateSave: false,
        "lengthMenu":[[25,50,75,-1],[25,50,75,"All"]],
        "order": [[1,"asc"]]
    });
} );