$(document).on("page:change", function() {
    $(".alert").addClass("in");
    window.setTimeout(function() {
        $(".alert").fadeTo(500, 0).slideUp(500, function(){
            $(this).remove();
        });
    }, 5000);
});
