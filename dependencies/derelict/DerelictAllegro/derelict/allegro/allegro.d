/*

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

*/
module derelict.allegro.allegro;

public
{
    import derelict.allegro.allegrotypes;
    import derelict.allegro.allegrofuncs;
}

private
{
    import derelict.util.loader;
}

class DerelictAllegroLoader : SharedLibLoader
{
public:
    this()
    {
        super(
            // Windows
            "allegro-5.0.5-mt.dll,allegro-5.0.4-mt.dll,allegro-5.0.3-mt.dll,allegro-5.0.2-mt.dll,"
            "allegro-5.0.1-mt.dll,allegro-5.0.0-mt.dll",
            // Linux
            "liballegro-5.0.5.so,liballegro-5.0.so",
            // OSX
            "../Frameworks/Allegro-5.0.framework,/Library/Frameworks/Allegro-5.0.framwork,"
            "liballegro-5.0.5.dylib,liballegro-5.0.dylib"
        );
    }

protected:
    override void loadSymbols()
    {
        bindFunc(cast(void**)&al_get_time, "al_get_time");
        bindFunc(cast(void**)&al_rest, "al_rest");
        bindFunc(cast(void**)&al_init_timeout, "al_init_timeout");
        bindFunc(cast(void**)&al_get_allegro_version, "al_get_allegro_version");
        bindFunc(cast(void**)&al_run_main, "al_run_main");
        bindFunc(cast(void**)&al_set_new_bitmap_format, "al_set_new_bitmap_format");
        bindFunc(cast(void**)&al_set_new_bitmap_flags, "al_set_new_bitmap_flags");
        bindFunc(cast(void**)&al_get_new_bitmap_format, "al_get_new_bitmap_format");
        bindFunc(cast(void**)&al_get_new_bitmap_flags, "al_get_new_bitmap_flags");
        bindFunc(cast(void**)&al_add_new_bitmap_flag, "al_add_new_bitmap_flag");
        bindFunc(cast(void**)&al_get_bitmap_width, "al_get_bitmap_width");
        bindFunc(cast(void**)&al_get_bitmap_height, "al_get_bitmap_height");
        bindFunc(cast(void**)&al_get_bitmap_format, "al_get_bitmap_format");
        bindFunc(cast(void**)&al_get_bitmap_flags, "al_get_bitmap_flags");
        bindFunc(cast(void**)&al_create_bitmap, "al_create_bitmap");
        bindFunc(cast(void**)&al_destroy_bitmap, "al_destroy_bitmap");
        bindFunc(cast(void**)&al_draw_bitmap, "al_draw_bitmap");
        bindFunc(cast(void**)&al_draw_bitmap_region, "al_draw_bitmap_region");
        bindFunc(cast(void**)&al_draw_scaled_bitmap, "al_draw_scaled_bitmap");
        bindFunc(cast(void**)&al_draw_rotated_bitmap, "al_draw_rotated_bitmap");
        bindFunc(cast(void**)&al_draw_scaled_rotated_bitmap, "al_draw_scaled_rotated_bitmap");
        bindFunc(cast(void**)&al_draw_tinted_bitmap, "al_draw_tinted_bitmap");
        bindFunc(cast(void**)&al_draw_tinted_bitmap_region, "al_draw_tinted_bitmap_region");
        bindFunc(cast(void**)&al_draw_tinted_scaled_bitmap, "al_draw_tinted_scaled_bitmap");
        bindFunc(cast(void**)&al_draw_tinted_rotated_bitmap, "al_draw_tinted_rotated_bitmap");
        bindFunc(cast(void**)&al_draw_tinted_scaled_rotated_bitmap, "al_draw_tinted_scaled_rotated_bitmap");
        bindFunc(cast(void**)&al_lock_bitmap, "al_lock_bitmap");
        bindFunc(cast(void**)&al_lock_bitmap_region, "al_lock_bitmap_region");
        bindFunc(cast(void**)&al_unlock_bitmap, "al_unlock_bitmap");
        bindFunc(cast(void**)&al_put_pixel, "al_put_pixel");
        bindFunc(cast(void**)&al_put_blended_pixel, "al_put_blended_pixel");
        bindFunc(cast(void**)&al_get_pixel, "al_get_pixel");
        bindFunc(cast(void**)&al_get_pixel_size, "al_get_pixel_size");
        /*
        bindFunc(cast(void**)&al_map_rgb, "al_map_rgb");
        bindFunc(cast(void**)&al_map_rgba, "al_map_rgba");
        bindFunc(cast(void**)&al_map_rgb_f, "al_map_rgb_f");
        bindFunc(cast(void**)&al_map_rgba_f, "al_map_rgba_f");
        */
        bindFunc(cast(void**)&al_unmap_rgb, "al_unmap_rgb");
        bindFunc(cast(void**)&al_unmap_rgba, "al_unmap_rgba");
        bindFunc(cast(void**)&al_unmap_rgb_f, "al_unmap_rgb_f");
        bindFunc(cast(void**)&al_unmap_rgba_f, "al_unmap_rgba_f");
        bindFunc(cast(void**)&al_get_pixel_format_bits, "al_get_pixel_format_bits");
        bindFunc(cast(void**)&al_convert_mask_to_alpha, "al_convert_mask_to_alpha");
        bindFunc(cast(void**)&al_set_clipping_rectangle, "al_set_clipping_rectangle");
        bindFunc(cast(void**)&al_get_clipping_rectangle, "al_get_clipping_rectangle");
        bindFunc(cast(void**)&al_create_sub_bitmap, "al_create_sub_bitmap");
        bindFunc(cast(void**)&al_is_sub_bitmap, "al_is_sub_bitmap");
        bindFunc(cast(void**)&al_clone_bitmap, "al_clone_bitmap");
        bindFunc(cast(void**)&al_is_bitmap_locked, "al_is_bitmap_locked");
        bindFunc(cast(void**)&al_set_blender, "al_set_blender");
        bindFunc(cast(void**)&al_get_blender, "al_get_blender");
        bindFunc(cast(void**)&al_set_separate_blender, "al_set_separate_blender");
        bindFunc(cast(void**)&al_get_separate_blender, "al_get_separate_blender");
        bindFunc(cast(void**)&_al_put_pixel, "_al_put_pixel");
        bindFunc(cast(void**)&al_register_bitmap_loader, "al_register_bitmap_loader");
        bindFunc(cast(void**)&al_register_bitmap_saver, "al_register_bitmap_saver");
        bindFunc(cast(void**)&al_register_bitmap_loader_f, "al_register_bitmap_loader_f");
        bindFunc(cast(void**)&al_register_bitmap_saver_f, "al_register_bitmap_saver_f");
        bindFunc(cast(void**)&al_load_bitmap, "al_load_bitmap");
        bindFunc(cast(void**)&al_load_bitmap_f, "al_load_bitmap_f");
        bindFunc(cast(void**)&al_save_bitmap, "al_save_bitmap");
        bindFunc(cast(void**)&al_save_bitmap_f, "al_save_bitmap_f");
        bindFunc(cast(void**)&al_create_config, "al_create_config");
        bindFunc(cast(void**)&al_add_config_section, "al_add_config_section");
        bindFunc(cast(void**)&al_set_config_value, "al_set_config_value");
        bindFunc(cast(void**)&al_add_config_comment, "al_add_config_comment");
        bindFunc(cast(void**)&al_get_config_value, "al_get_config_value");
        bindFunc(cast(void**)&al_load_config_file, "al_load_config_file");
        bindFunc(cast(void**)&al_load_config_file_f, "al_load_config_file_f");
        bindFunc(cast(void**)&al_save_config_file, "al_save_config_file");
        bindFunc(cast(void**)&al_save_config_file_f, "al_save_config_file_f");
        bindFunc(cast(void**)&al_merge_config_into, "al_merge_config_into");
        bindFunc(cast(void**)&al_merge_config, "al_merge_config");
        bindFunc(cast(void**)&al_destroy_config, "al_destroy_config");
        bindFunc(cast(void**)&al_get_first_config_section, "al_get_first_config_section");
        bindFunc(cast(void**)&al_get_next_config_section, "al_get_next_config_section");
        bindFunc(cast(void**)&al_get_first_config_entry, "al_get_first_config_entry");
        bindFunc(cast(void**)&al_get_next_config_entry, "al_get_next_config_entry");
        bindFunc(cast(void**)&al_set_new_display_refresh_rate, "al_set_new_display_refresh_rate");
        bindFunc(cast(void**)&al_set_new_display_flags, "al_set_new_display_flags");
        bindFunc(cast(void**)&al_get_new_display_refresh_rate, "al_get_new_display_refresh_rate");
        bindFunc(cast(void**)&al_get_new_display_flags, "al_get_new_display_flags");
        bindFunc(cast(void**)&al_get_display_width, "al_get_display_width");
        bindFunc(cast(void**)&al_get_display_height, "al_get_display_height");
        bindFunc(cast(void**)&al_get_display_format, "al_get_display_format");
        bindFunc(cast(void**)&al_get_display_refresh_rate, "al_get_display_refresh_rate");
        bindFunc(cast(void**)&al_get_display_flags, "al_get_display_flags");
        bindFunc(cast(void**)&al_create_display, "al_create_display");
        bindFunc(cast(void**)&al_destroy_display, "al_destroy_display");
        bindFunc(cast(void**)&al_get_current_display, "al_get_current_display");
        bindFunc(cast(void**)&al_set_target_bitmap, "al_set_target_bitmap");
        bindFunc(cast(void**)&al_set_target_backbuffer, "al_set_target_backbuffer");
        bindFunc(cast(void**)&al_get_backbuffer, "al_get_backbuffer");
        bindFunc(cast(void**)&al_get_target_bitmap, "al_get_target_bitmap");
        bindFunc(cast(void**)&al_acknowledge_resize, "al_acknowledge_resize");
        bindFunc(cast(void**)&al_resize_display, "al_resize_display");
        bindFunc(cast(void**)&al_flip_display, "al_flip_display");
        bindFunc(cast(void**)&al_update_display_region, "al_update_display_region");
        bindFunc(cast(void**)&al_is_compatible_bitmap, "al_is_compatible_bitmap");
        bindFunc(cast(void**)&al_get_num_display_modes, "al_get_num_display_modes");
        bindFunc(cast(void**)&al_get_display_mode, "al_get_display_mode");
        bindFunc(cast(void**)&al_wait_for_vsync, "al_wait_for_vsync");
        bindFunc(cast(void**)&al_get_display_event_source, "al_get_display_event_source");
        bindFunc(cast(void**)&al_clear_to_color, "al_clear_to_color");
        bindFunc(cast(void**)&al_draw_pixel, "al_draw_pixel");
        bindFunc(cast(void**)&al_set_display_icon, "al_set_display_icon");
        bindFunc(cast(void**)&al_get_num_video_adapters, "al_get_num_video_adapters");
        bindFunc(cast(void**)&al_get_monitor_info, "al_get_monitor_info");
        bindFunc(cast(void**)&al_get_new_display_adapter, "al_get_new_display_adapter");
        bindFunc(cast(void**)&al_set_new_display_adapter, "al_set_new_display_adapter");
        bindFunc(cast(void**)&al_set_new_window_position, "al_set_new_window_position");
        bindFunc(cast(void**)&al_get_new_window_position, "al_get_new_window_position");
        bindFunc(cast(void**)&al_set_window_position, "al_set_window_position");
        bindFunc(cast(void**)&al_get_window_position, "al_get_window_position");
        bindFunc(cast(void**)&al_set_window_title, "al_set_window_title");
        bindFunc(cast(void**)&al_set_new_display_option, "al_set_new_display_option");
        bindFunc(cast(void**)&al_get_new_display_option, "al_get_new_display_option");
        bindFunc(cast(void**)&al_reset_new_display_options, "al_reset_new_display_options");
        bindFunc(cast(void**)&al_get_display_option, "al_get_display_option");
        bindFunc(cast(void**)&al_hold_bitmap_drawing, "al_hold_bitmap_drawing");
        bindFunc(cast(void**)&al_is_bitmap_drawing_held, "al_is_bitmap_drawing_held");
        bindFunc(cast(void**)&al_get_errno, "al_get_errno");
        bindFunc(cast(void**)&al_set_errno, "al_set_errno");
        bindFunc(cast(void**)&al_init_user_event_source, "al_init_user_event_source");
        bindFunc(cast(void**)&al_destroy_user_event_source, "al_destroy_user_event_source");
        bindFunc(cast(void**)&al_emit_user_event, "al_emit_user_event");
        bindFunc(cast(void**)&al_unref_user_event, "al_unref_user_event");
        bindFunc(cast(void**)&al_set_event_source_data, "al_set_event_source_data");
        bindFunc(cast(void**)&al_get_event_source_data, "al_get_event_source_data");
        bindFunc(cast(void**)&al_create_event_queue, "al_create_event_queue");
        bindFunc(cast(void**)&al_destroy_event_queue, "al_destroy_event_queue");
        bindFunc(cast(void**)&al_register_event_source, "al_register_event_source");
        bindFunc(cast(void**)&al_unregister_event_source, "al_unregister_event_source");
        bindFunc(cast(void**)&al_is_event_queue_empty, "al_is_event_queue_empty");
        bindFunc(cast(void**)&al_get_next_event, "al_get_next_event");
        bindFunc(cast(void**)&al_peek_next_event, "al_peek_next_event");
        bindFunc(cast(void**)&al_drop_next_event, "al_drop_next_event");
        bindFunc(cast(void**)&al_flush_event_queue, "al_flush_event_queue");
        bindFunc(cast(void**)&al_wait_for_event, "al_wait_for_event");
        bindFunc(cast(void**)&al_wait_for_event_timed, "al_wait_for_event_timed");
        bindFunc(cast(void**)&al_wait_for_event_until, "al_wait_for_event_until");
        bindFunc(cast(void**)&al_fopen, "al_fopen");
        bindFunc(cast(void**)&al_fopen_interface, "al_fopen_interface");
        bindFunc(cast(void**)&al_create_file_handle, "al_create_file_handle");
        bindFunc(cast(void**)&al_fclose, "al_fclose");
        bindFunc(cast(void**)&al_fread, "al_fread");
        bindFunc(cast(void**)&al_fwrite, "al_fwrite");
        bindFunc(cast(void**)&al_fflush, "al_fflush");
        bindFunc(cast(void**)&al_ftell, "al_ftell");
        bindFunc(cast(void**)&al_fseek, "al_fseek");
        bindFunc(cast(void**)&al_feof, "al_feof");
        bindFunc(cast(void**)&al_ferror, "al_ferror");
        bindFunc(cast(void**)&al_fclearerr, "al_fclearerr");
        bindFunc(cast(void**)&al_fungetc, "al_fungetc");
        bindFunc(cast(void**)&al_fsize, "al_fsize");
        bindFunc(cast(void**)&al_fgetc, "al_fgetc");
        bindFunc(cast(void**)&al_fputc, "al_fputc");
        bindFunc(cast(void**)&al_fread16le, "al_fread16le");
        bindFunc(cast(void**)&al_fread16be, "al_fread16be");
        bindFunc(cast(void**)&al_fwrite16le, "al_fwrite16le");
        bindFunc(cast(void**)&al_fwrite16be, "al_fwrite16be");
        bindFunc(cast(void**)&al_fgets, "al_fgets");
        bindFunc(cast(void**)&al_fget_ustr, "al_fget_ustr");
        bindFunc(cast(void**)&al_fputs, "al_fputs");
        bindFunc(cast(void**)&al_fopen_fd, "al_fopen_fd");
        bindFunc(cast(void**)&al_make_temp_file, "al_make_temp_file");
        bindFunc(cast(void**)&al_get_file_userdata, "al_get_file_userdata");
        bindFunc(cast(void**)&al_create_fs_entry, "al_create_fs_entry");
        bindFunc(cast(void**)&al_destroy_fs_entry, "al_destroy_fs_entry");
        bindFunc(cast(void**)&al_get_fs_entry_name, "al_get_fs_entry_name");
        bindFunc(cast(void**)&al_update_fs_entry, "al_update_fs_entry");
        bindFunc(cast(void**)&al_get_fs_entry_mode, "al_get_fs_entry_mode");
        bindFunc(cast(void**)&al_get_fs_entry_atime, "al_get_fs_entry_atime");
        bindFunc(cast(void**)&al_get_fs_entry_mtime, "al_get_fs_entry_mtime");
        bindFunc(cast(void**)&al_get_fs_entry_ctime, "al_get_fs_entry_ctime");
        bindFunc(cast(void**)&al_get_fs_entry_size, "al_get_fs_entry_size");
        bindFunc(cast(void**)&al_fs_entry_exists, "al_fs_entry_exists");
        bindFunc(cast(void**)&al_remove_fs_entry, "al_remove_fs_entry");
        bindFunc(cast(void**)&al_open_directory, "al_open_directory");
        bindFunc(cast(void**)&al_read_directory, "al_read_directory");
        bindFunc(cast(void**)&al_close_directory, "al_close_directory");
        bindFunc(cast(void**)&al_filename_exists, "al_filename_exists");
        bindFunc(cast(void**)&al_remove_filename, "al_remove_filename");
        bindFunc(cast(void**)&al_get_current_directory, "al_get_current_directory");
        bindFunc(cast(void**)&al_change_directory, "al_change_directory");
        bindFunc(cast(void**)&al_make_directory, "al_make_directory");
        bindFunc(cast(void**)&al_open_fs_entry, "al_open_fs_entry");
        bindFunc(cast(void**)&al_get_fs_interface, "al_get_fs_interface");
        bindFunc(cast(void**)&al_set_fs_interface, "al_set_fs_interface");
        bindFunc(cast(void**)&al_set_standard_fs_interface, "al_set_standard_fs_interface");
        bindFunc(cast(void**)&al_install_joystick, "al_install_joystick");
        bindFunc(cast(void**)&al_uninstall_joystick, "al_uninstall_joystick");
        bindFunc(cast(void**)&al_is_joystick_installed, "al_is_joystick_installed");
        bindFunc(cast(void**)&al_reconfigure_joysticks, "al_reconfigure_joysticks");
        bindFunc(cast(void**)&al_get_num_joysticks, "al_get_num_joysticks");
        bindFunc(cast(void**)&al_get_joystick, "al_get_joystick");
        bindFunc(cast(void**)&al_release_joystick, "al_release_joystick");
        bindFunc(cast(void**)&al_get_joystick_active, "al_get_joystick_active");
        bindFunc(cast(void**)&al_get_joystick_name, "al_get_joystick_name");
        bindFunc(cast(void**)&al_get_joystick_num_sticks, "al_get_joystick_num_sticks");
        bindFunc(cast(void**)&al_get_joystick_stick_flags, "al_get_joystick_stick_flags");
        bindFunc(cast(void**)&al_get_joystick_stick_name, "al_get_joystick_stick_name");
        bindFunc(cast(void**)&al_get_joystick_num_axes, "al_get_joystick_num_axes");
        bindFunc(cast(void**)&al_get_joystick_axis_name, "al_get_joystick_axis_name");
        bindFunc(cast(void**)&al_get_joystick_num_buttons, "al_get_joystick_num_buttons");
        bindFunc(cast(void**)&al_get_joystick_button_name, "al_get_joystick_button_name");
        bindFunc(cast(void**)&al_get_joystick_state, "al_get_joystick_state");
        bindFunc(cast(void**)&al_get_joystick_event_source, "al_get_joystick_event_source");
        bindFunc(cast(void**)&al_is_keyboard_installed, "al_is_keyboard_installed");
        bindFunc(cast(void**)&al_install_keyboard, "al_install_keyboard");
        bindFunc(cast(void**)&al_uninstall_keyboard, "al_uninstall_keyboard");
        bindFunc(cast(void**)&al_set_keyboard_leds, "al_set_keyboard_leds");
        bindFunc(cast(void**)&al_keycode_to_name, "al_keycode_to_name");
        bindFunc(cast(void**)&al_get_keyboard_state, "al_get_keyboard_state");
        bindFunc(cast(void**)&al_key_down, "al_key_down");
        bindFunc(cast(void**)&al_get_keyboard_event_source, "al_get_keyboard_event_source");
        bindFunc(cast(void**)&al_set_memory_interface, "al_set_memory_interface");
        bindFunc(cast(void**)&al_malloc_with_context, "al_malloc_with_context");
        bindFunc(cast(void**)&al_free_with_context, "al_free_with_context");
        bindFunc(cast(void**)&al_realloc_with_context, "al_realloc_with_context");
        bindFunc(cast(void**)&al_calloc_with_context, "al_calloc_with_context");
        bindFunc(cast(void**)&al_is_mouse_installed, "al_is_mouse_installed");
        bindFunc(cast(void**)&al_install_mouse, "al_install_mouse");
        bindFunc(cast(void**)&al_uninstall_mouse, "al_uninstall_mouse");
        bindFunc(cast(void**)&al_get_mouse_num_buttons, "al_get_mouse_num_buttons");
        bindFunc(cast(void**)&al_get_mouse_num_axes, "al_get_mouse_num_axes");
        bindFunc(cast(void**)&al_set_mouse_xy, "al_set_mouse_xy");
        bindFunc(cast(void**)&al_set_mouse_z, "al_set_mouse_z");
        bindFunc(cast(void**)&al_set_mouse_w, "al_set_mouse_w");
        bindFunc(cast(void**)&al_set_mouse_axis, "al_set_mouse_axis");
        bindFunc(cast(void**)&al_get_mouse_state, "al_get_mouse_state");
        bindFunc(cast(void**)&al_mouse_button_down, "al_mouse_button_down");
        bindFunc(cast(void**)&al_get_mouse_state_axis, "al_get_mouse_state_axis");
        bindFunc(cast(void**)&al_get_mouse_event_source, "al_get_mouse_event_source");
        bindFunc(cast(void**)&al_create_mouse_cursor, "al_create_mouse_cursor");
        bindFunc(cast(void**)&al_destroy_mouse_cursor, "al_destroy_mouse_cursor");
        bindFunc(cast(void**)&al_set_mouse_cursor, "al_set_mouse_cursor");
        bindFunc(cast(void**)&al_set_system_mouse_cursor, "al_set_system_mouse_cursor");
        bindFunc(cast(void**)&al_show_mouse_cursor, "al_show_mouse_cursor");
        bindFunc(cast(void**)&al_hide_mouse_cursor, "al_hide_mouse_cursor");
        bindFunc(cast(void**)&al_get_mouse_cursor_position, "al_get_mouse_cursor_position");
        bindFunc(cast(void**)&al_grab_mouse, "al_grab_mouse");
        bindFunc(cast(void**)&al_ungrab_mouse, "al_ungrab_mouse");
        bindFunc(cast(void**)&al_create_path, "al_create_path");
        bindFunc(cast(void**)&al_create_path_for_directory, "al_create_path_for_directory");
        bindFunc(cast(void**)&al_clone_path, "al_clone_path");
        bindFunc(cast(void**)&al_get_path_num_components, "al_get_path_num_components");
        bindFunc(cast(void**)&al_get_path_component, "al_get_path_component");
        bindFunc(cast(void**)&al_replace_path_component, "al_replace_path_component");
        bindFunc(cast(void**)&al_remove_path_component, "al_remove_path_component");
        bindFunc(cast(void**)&al_insert_path_component, "al_insert_path_component");
        bindFunc(cast(void**)&al_get_path_tail, "al_get_path_tail");
        bindFunc(cast(void**)&al_drop_path_tail, "al_drop_path_tail");
        bindFunc(cast(void**)&al_append_path_component, "al_append_path_component");
        bindFunc(cast(void**)&al_join_paths, "al_join_paths");
        bindFunc(cast(void**)&al_rebase_path, "al_rebase_path");
        bindFunc(cast(void**)&al_path_cstr, "al_path_cstr");
        bindFunc(cast(void**)&al_destroy_path, "al_destroy_path");
        bindFunc(cast(void**)&al_set_path_drive, "al_set_path_drive");
        bindFunc(cast(void**)&al_get_path_drive, "al_get_path_drive");
        bindFunc(cast(void**)&al_set_path_filename, "al_set_path_filename");
        bindFunc(cast(void**)&al_get_path_filename, "al_get_path_filename");
        bindFunc(cast(void**)&al_get_path_extension, "al_get_path_extension");
        bindFunc(cast(void**)&al_set_path_extension, "al_set_path_extension");
        bindFunc(cast(void**)&al_get_path_basename, "al_get_path_basename");
        bindFunc(cast(void**)&al_make_path_canonical, "al_make_path_canonical");
        bindFunc(cast(void**)&al_install_system, "al_install_system");
        bindFunc(cast(void**)&al_uninstall_system, "al_uninstall_system");
        bindFunc(cast(void**)&al_is_system_installed, "al_is_system_installed");
        bindFunc(cast(void**)&al_get_system_driver, "al_get_system_driver");
        bindFunc(cast(void**)&al_get_system_config, "al_get_system_config");
        bindFunc(cast(void**)&al_get_standard_path, "al_get_standard_path");
        bindFunc(cast(void**)&al_set_org_name, "al_set_org_name");
        bindFunc(cast(void**)&al_set_app_name, "al_set_app_name");
        bindFunc(cast(void**)&al_get_org_name, "al_get_org_name");
        bindFunc(cast(void**)&al_get_app_name, "al_get_app_name");
        bindFunc(cast(void**)&al_inhibit_screensaver, "al_inhibit_screensaver");
        bindFunc(cast(void**)&al_create_thread, "al_create_thread");
        bindFunc(cast(void**)&al_start_thread, "al_start_thread");
        bindFunc(cast(void**)&al_join_thread, "al_join_thread");
        bindFunc(cast(void**)&al_set_thread_should_stop, "al_set_thread_should_stop");
        bindFunc(cast(void**)&al_get_thread_should_stop, "al_get_thread_should_stop");
        bindFunc(cast(void**)&al_destroy_thread, "al_destroy_thread");
        bindFunc(cast(void**)&al_run_detached_thread, "al_run_detached_thread");
        bindFunc(cast(void**)&al_create_mutex, "al_create_mutex");
        bindFunc(cast(void**)&al_create_mutex_recursive, "al_create_mutex_recursive");
        bindFunc(cast(void**)&al_lock_mutex, "al_lock_mutex");
        bindFunc(cast(void**)&al_unlock_mutex, "al_unlock_mutex");
        bindFunc(cast(void**)&al_destroy_mutex, "al_destroy_mutex");
        bindFunc(cast(void**)&al_create_cond, "al_create_cond");
        bindFunc(cast(void**)&al_destroy_cond, "al_destroy_cond");
        bindFunc(cast(void**)&al_wait_cond, "al_wait_cond");
        bindFunc(cast(void**)&al_wait_cond_until, "al_wait_cond_until");
        bindFunc(cast(void**)&al_broadcast_cond, "al_broadcast_cond");
        bindFunc(cast(void**)&al_signal_cond, "al_signal_cond");
        bindFunc(cast(void**)&al_create_timer, "al_create_timer");
        bindFunc(cast(void**)&al_destroy_timer, "al_destroy_timer");
        bindFunc(cast(void**)&al_start_timer, "al_start_timer");
        bindFunc(cast(void**)&al_stop_timer, "al_stop_timer");
        bindFunc(cast(void**)&al_get_timer_started, "al_get_timer_started");
        bindFunc(cast(void**)&al_get_timer_speed, "al_get_timer_speed");
        bindFunc(cast(void**)&al_set_timer_speed, "al_set_timer_speed");
        bindFunc(cast(void**)&al_get_timer_count, "al_get_timer_count");
        bindFunc(cast(void**)&al_set_timer_count, "al_set_timer_count");
        bindFunc(cast(void**)&al_add_timer_count, "al_add_timer_count");
        bindFunc(cast(void**)&al_get_timer_event_source, "al_get_timer_event_source");
        bindFunc(cast(void**)&al_store_state, "al_store_state");
        bindFunc(cast(void**)&al_restore_state, "al_restore_state");
        bindFunc(cast(void**)&al_use_transform, "al_use_transform");
        bindFunc(cast(void**)&al_copy_transform, "al_copy_transform");
        bindFunc(cast(void**)&al_identity_transform, "al_identity_transform");
        bindFunc(cast(void**)&al_build_transform, "al_build_transform");
        bindFunc(cast(void**)&al_translate_transform, "al_translate_transform");
        bindFunc(cast(void**)&al_rotate_transform, "al_rotate_transform");
        bindFunc(cast(void**)&al_scale_transform, "al_scale_transform");
        bindFunc(cast(void**)&al_transform_coordinates, "al_transform_coordinates");
        bindFunc(cast(void**)&al_compose_transform, "al_compose_transform");
        bindFunc(cast(void**)&al_get_current_transform, "al_get_current_transform");
        bindFunc(cast(void**)&al_invert_transform, "al_invert_transform");
        bindFunc(cast(void**)&al_check_inverse, "al_check_inverse");

        bindFunc(cast(void**)&al_ustr_new, "al_ustr_new");
        bindFunc(cast(void**)&al_ustr_new_from_buffer, "al_ustr_new_from_buffer");
        bindFunc(cast(void**)&al_ustr_newf, "al_ustr_newf");
        bindFunc(cast(void**)&al_ustr_free, "al_ustr_free");
        bindFunc(cast(void**)&al_cstr, "al_cstr");
        bindFunc(cast(void**)&al_ustr_to_buffer, "al_ustr_to_buffer");
        bindFunc(cast(void**)&al_cstr_dup, "al_cstr_dup");
        bindFunc(cast(void**)&al_ustr_dup, "al_ustr_dup");
        bindFunc(cast(void**)&al_ustr_dup_substr, "al_ustr_dup_substr");
        bindFunc(cast(void**)&al_ustr_empty_string, "al_ustr_empty_string");
        bindFunc(cast(void**)&al_ref_cstr, "al_ref_cstr");
        bindFunc(cast(void**)&al_ref_buffer, "al_ref_buffer");
        bindFunc(cast(void**)&al_ref_ustr, "al_ref_ustr");
        bindFunc(cast(void**)&al_destroy_thread, "al_destroy_thread");
        bindFunc(cast(void**)&al_ustr_size, "al_ustr_size");
        bindFunc(cast(void**)&al_ustr_length, "al_ustr_length");
        bindFunc(cast(void**)&al_ustr_offset, "al_ustr_offset");
        bindFunc(cast(void**)&al_ustr_next, "al_ustr_next");
        bindFunc(cast(void**)&al_ustr_prev, "al_ustr_prev");
        bindFunc(cast(void**)&al_ustr_get, "al_ustr_get");
        bindFunc(cast(void**)&al_ustr_get_next, "al_ustr_get_next");
        bindFunc(cast(void**)&al_ustr_prev_get, "al_ustr_prev_get");
        bindFunc(cast(void**)&al_ustr_insert, "al_ustr_insert");
        bindFunc(cast(void**)&al_ustr_insert_cstr, "al_ustr_insert_cstr");
        bindFunc(cast(void**)&al_ustr_insert_chr, "al_ustr_insert_chr");
        bindFunc(cast(void**)&al_ustr_append, "al_ustr_append");
        bindFunc(cast(void**)&al_ustr_append_cstr, "al_ustr_append_cstr");
        bindFunc(cast(void**)&al_ustr_append_chr, "al_ustr_append_chr");
        bindFunc(cast(void**)&al_ustr_appendf, "al_ustr_appendf");
        bindFunc(cast(void**)&al_ustr_vappendf, "al_ustr_vappendf");
        bindFunc(cast(void**)&al_ustr_remove_chr, "al_ustr_remove_chr");
        bindFunc(cast(void**)&al_ustr_remove_range, "al_ustr_remove_range");
        bindFunc(cast(void**)&al_ustr_truncate, "al_ustr_truncate");
        bindFunc(cast(void**)&al_ustr_ltrim_ws, "al_ustr_ltrim_ws");
        bindFunc(cast(void**)&al_ustr_rtrim_ws, "al_ustr_rtrim_ws");
        bindFunc(cast(void**)&al_ustr_trim_ws, "al_ustr_trim_ws");
        bindFunc(cast(void**)&al_ustr_assign, "al_ustr_assign");
        bindFunc(cast(void**)&al_ustr_assign_substr, "al_ustr_assign_substr");
        bindFunc(cast(void**)&al_ustr_assign_cstr, "al_ustr_assign_cstr");
        bindFunc(cast(void**)&al_ustr_set_chr, "al_ustr_set_chr");
        bindFunc(cast(void**)&al_ustr_replace_range, "al_ustr_replace_range");
        bindFunc(cast(void**)&al_ustr_find_chr, "al_ustr_find_chr");
        bindFunc(cast(void**)&al_ustr_rfind_chr, "al_ustr_rfind_chr");
        bindFunc(cast(void**)&al_ustr_find_set, "al_ustr_find_set");
        bindFunc(cast(void**)&al_ustr_find_set_cstr, "al_ustr_find_set_cstr");
        bindFunc(cast(void**)&al_ustr_find_cset, "al_ustr_find_cset");
        bindFunc(cast(void**)&al_ustr_find_cset_cstr, "al_ustr_find_cset_cstr");
        bindFunc(cast(void**)&al_ustr_find_str, "al_ustr_find_str");
        bindFunc(cast(void**)&al_ustr_find_cstr, "al_ustr_find_cstr");
        bindFunc(cast(void**)&al_ustr_rfind_str, "al_ustr_rfind_str");
        bindFunc(cast(void**)&al_ustr_rfind_cstr, "al_ustr_rfind_cstr");
        bindFunc(cast(void**)&al_ustr_find_replace, "al_ustr_find_replace");
        bindFunc(cast(void**)&al_uninstall_system, "al_uninstall_system");
        bindFunc(cast(void**)&al_ustr_find_replace_cstr, "al_ustr_find_replace_cstr");
        bindFunc(cast(void**)&al_ustr_equal, "al_ustr_equal");
        bindFunc(cast(void**)&al_ustr_compare, "al_ustr_compare");
        bindFunc(cast(void**)&al_ustr_ncompare, "al_ustr_ncompare");
        bindFunc(cast(void**)&al_ustr_has_prefix, "al_ustr_has_prefix");
        bindFunc(cast(void**)&al_ustr_has_prefix_cstr, "al_ustr_has_prefix_cstr");
        bindFunc(cast(void**)&al_ustr_has_suffix, "al_ustr_has_suffix");
        bindFunc(cast(void**)&al_ustr_has_suffix_cstr, "al_ustr_has_suffix_cstr");
        bindFunc(cast(void**)&al_utf8_width, "al_utf8_width");
        bindFunc(cast(void**)&al_utf8_encode, "al_utf8_encode");
        bindFunc(cast(void**)&al_ustr_new_from_utf16, "al_ustr_new_from_utf16");
        bindFunc(cast(void**)&al_ustr_size_utf16, "al_ustr_size_utf16");
        bindFunc(cast(void**)&al_ustr_encode_utf16, "al_ustr_encode_utf16");
        bindFunc(cast(void**)&al_utf16_width, "al_utf16_width");
        bindFunc(cast(void**)&al_utf16_encode, "al_utf16_encode");
    }
}

DerelictAllegroLoader DerelictAllegro;

static this()
{
    DerelictAllegro = new DerelictAllegroLoader();
}

static ~this()
{
    if(SharedLibLoader.isAutoUnloadEnabled())
        DerelictAllegro.unload();
}